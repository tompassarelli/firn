use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};

const PROBE: &str = r#"set -euo pipefail
printf '@uid %s\n' "$(id -u)"
systemctl --user list-units --plain --no-legend --state=active 'smashcraft-lan-pool-*' | awk '{print "@pool", $1}'
if command -v podman >/dev/null; then podman ps --no-trunc --format '@container {{.ID}} {{.Names}}'; fi
north="$(command -v north || echo "$HOME/.local/bin/north")"
if [ -x "$north" ]; then echo @fleet; "$north" fleet list --json; echo; echo @fleet-end; fi
ps -eo cgroup=,args= | awk '/Runner[.]Worker/ && match($0, /libpod-[0-9a-f]+/) {print "@job", substr($0, RSTART + 7, RLENGTH - 7)}'
echo @end
"#;
const USAGE: &str = "usage: firn host idle <host> | firn host restart-user-manager <host>";

#[derive(Debug, Default, PartialEq)]
struct Probe {
    uid: Option<u32>,
    pools: Vec<String>,
    containers: Vec<(String, String)>,
    jobs: Vec<String>,
    fleet: Option<String>,
}

pub fn run() {
    let args: Vec<String> = std::env::args().skip(2).collect();
    let (edge, host) = match args.as_slice() {
        [node, edge, host] if node == "host" => (edge.as_str(), host.as_str()),
        [edge, host] => (edge.as_str(), host.as_str()),
        _ => fail(USAGE, 64),
    };
    let restart = match edge {
        "idle" => false,
        "restart-user-manager" => true,
        _ => fail(USAGE, 64),
    };
    let host = host.rsplit('@').next().unwrap_or(host);
    let (uid, blockers) = match inspect(host) {
        Ok(found) => found,
        Err(error) => fail(
            &format!("firn host {edge}: cannot verify that {host} is idle: {error}"),
            1,
        ),
    };
    if !blockers.is_empty() {
        let verb = if restart {
            "refusing to restart its user manager"
        } else {
            "busy"
        };
        eprintln!("firn host {edge}: {host} is in use; {verb}:");
        for blocker in &blockers {
            eprintln!("  - {blocker}");
        }
        std::process::exit(1);
    }
    println!(
        "{host} is idle: no busy farm runner job, no fleet session on it, no running containers, no LAN pool units"
    );
    if restart {
        let unit = format!("user@{uid}.service");
        println!("restarting {unit} on {host}");
        let status = Command::new("ssh")
            .args([
                "-o",
                "BatchMode=yes",
                &format!("root@{host}"),
                "systemctl",
                "restart",
                &unit,
            ])
            .status();
        if !status.is_ok_and(|status| status.success()) {
            fail(
                &format!("firn host restart-user-manager: restarting {unit} on {host} failed"),
                1,
            );
        }
    }
}

fn fail(message: &str, code: i32) -> ! {
    eprintln!("{message}");
    std::process::exit(code)
}

fn inspect(host: &str) -> Result<(u32, Vec<String>), String> {
    let probe = remote_probe(host)?;
    let fleet = command_output(
        Command::new("north").args(["fleet", "list", "--json"]),
        None,
    )
    .map_err(|error| format!("north fleet list --json: {error}"))?;
    let fleet: Value = serde_json::from_str(&fleet)
        .map_err(|error| format!("north fleet list --json: {error}"))?;
    let host_fleet = match &probe.fleet {
        Some(json) => serde_json::from_str(json)
            .map_err(|error| format!("north fleet list --json on {host}: {error}"))?,
        None => Value::Null,
    };
    let uid = probe.uid.ok_or("the probe printed no uid")?;
    Ok((uid, blockers(host, &probe, &fleet, &host_fleet)))
}

fn remote_probe(host: &str) -> Result<Probe, String> {
    let output = command_output(
        Command::new("ssh").args([
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            host,
            "bash",
            "-s",
        ]),
        Some(PROBE),
    )
    .map_err(|error| format!("ssh {host}: {error}"))?;
    parse(&output).ok_or_else(|| format!("ssh {host}: the idle probe did not finish"))
}

fn command_output(command: &mut Command, input: Option<&str>) -> Result<String, String> {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let mut stdin = child.stdin.take().ok_or("no stdin")?;
    stdin
        .write_all(input.unwrap_or("").as_bytes())
        .map_err(|error| error.to_string())?;
    drop(stdin);
    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(format!(
            "{} {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    String::from_utf8(output.stdout).map_err(|error| error.to_string())
}

fn parse(output: &str) -> Option<Probe> {
    let mut probe = Probe::default();
    let mut finished = false;
    let mut fleet: Option<String> = None;
    for line in output.lines() {
        if let Some(json) = fleet.as_mut() {
            if line == "@fleet-end" {
                probe.fleet = fleet.take();
            } else {
                json.push_str(line);
                json.push('\n');
            }
            continue;
        }
        if line == "@fleet" {
            fleet = Some(String::new());
            continue;
        }
        let mut words = line.split_whitespace();
        match (words.next(), words.next(), words.next()) {
            (Some("@uid"), Some(uid), None) => probe.uid = uid.parse().ok(),
            (Some("@pool"), Some(unit), None) => probe.pools.push(unit.into()),
            (Some("@container"), Some(id), Some(name)) => {
                probe.containers.push((id.into(), name.into()))
            }
            (Some("@job"), Some(id), None) => probe.jobs.push(id.into()),
            (Some("@end"), None, None) => finished = true,
            _ => {}
        }
    }
    finished.then_some(probe)
}

fn blockers(host: &str, probe: &Probe, fleet: &Value, host_fleet: &Value) -> Vec<String> {
    let container = |id: &str| {
        probe
            .containers
            .iter()
            .find(|(full, _)| full.starts_with(id) || id.starts_with(full.as_str()))
    };
    let mut blockers: Vec<String> = probe
        .jobs
        .iter()
        .map(|id| match container(id) {
            Some((_, name)) => format!("farm runner job running in container {name}"),
            None => format!("farm runner job running in container {id}"),
        })
        .collect();
    let placed_here = fleet_sessions(fleet).filter(|entry| entry["machine"].as_str() == Some(host));
    let launched_there = fleet_sessions(host_fleet).filter(|entry| {
        entry["machine"]
            .as_str()
            .is_none_or(|machine| machine == host)
    });
    for entry in placed_here.chain(launched_there) {
        let blocker = format!(
            "fleet session {} ({}) on {host}",
            entry["name"].as_str().unwrap_or("?"),
            entry["status"].as_str().unwrap_or("?")
        );
        if !blockers.contains(&blocker) {
            blockers.push(blocker);
        }
    }
    blockers.extend(
        probe
            .containers
            .iter()
            .filter(|(_, name)| !name.starts_with("farm-"))
            .map(|(_, name)| format!("container {name} running")),
    );
    blockers.extend(
        probe
            .pools
            .iter()
            .map(|unit| format!("LAN pool unit {unit} active")),
    );
    blockers
}

fn fleet_sessions(fleet: &Value) -> impl Iterator<Item = &Value> {
    fleet
        .as_array()
        .into_iter()
        .flatten()
        .filter(|entry| !matches!(entry["status"].as_str(), Some("exited" | "forgotten")))
}
