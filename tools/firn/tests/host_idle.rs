use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

const BUSY_PROBE: &str = "@uid 1000\n@pool smashcraft-lan-pool-1.service\n@container a63b400ecb7f farm-smashcraft-3\n@container 77aa podman-scratch\n@job a63b400ecb7f\n@end\n";
const IDLE_PROBE: &str = "@uid 1000\n@container a63b400ecb7f farm-smashcraft-3\n@end\n";
const FLEET: &str = r#"[{"name":"sc-218-taps","status":"working","machine":"gex45"},{"name":"old","status":"exited","machine":"gex45"},{"name":"proxy","status":"idle","machine":null}]"#;

fn tool(dir: &Path, name: &str, body: &str) {
    let path = dir.join(name);
    fs::write(&path, format!("#!/usr/bin/env bash\n{body}\n")).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn run(edge: &str, probe: &str, fleet: &str) -> (Output, String) {
    let dir = tempfile_dir();
    fs::write(dir.join("probe"), probe).unwrap();
    fs::write(dir.join("fleet"), fleet).unwrap();
    let log = dir.join("ssh.log");
    tool(
        &dir,
        "ssh",
        &format!(
            "printf '%s\\n' \"$*\" >>{0}; case \"$*\" in *'bash -s') cat >/dev/null; cat {1} ;; esac",
            log.display(),
            dir.join("probe").display()
        ),
    );
    tool(
        &dir,
        "north",
        &format!("cat {}", dir.join("fleet").display()),
    );
    let path = format!("{}:{}", dir.display(), std::env::var("PATH").unwrap());
    let output = Command::new(env!("CARGO_BIN_EXE_firn-tools"))
        .args(["host", "host", edge, "tom@gex45"])
        .env("PATH", path)
        .output()
        .unwrap();
    let calls = fs::read_to_string(&log).unwrap_or_default();
    fs::remove_dir_all(&dir).unwrap();
    (output, calls)
}

fn tempfile_dir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "firn-host-idle-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn busy_host_refuses_and_names_every_blocker() {
    let (output, calls) = run("restart-user-manager", BUSY_PROBE, FLEET);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(1), "{stderr}");
    for blocker in [
        "farm runner job running in container farm-smashcraft-3",
        "fleet session sc-218-taps (working) on gex45",
        "container podman-scratch running",
        "LAN pool unit smashcraft-lan-pool-1.service active",
    ] {
        assert!(stderr.contains(blocker), "{blocker} missing from {stderr}");
    }
    assert!(!stderr.contains("old"), "{stderr}");
    assert!(!calls.contains("systemctl restart"), "{calls}");
}

#[test]
fn idle_host_restarts_only_its_user_manager() {
    let (output, calls) = run("restart-user-manager", IDLE_PROBE, "[]");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        calls.contains("-o BatchMode=yes root@gex45 systemctl restart user@1000.service"),
        "{calls}"
    );
    let (check, calls) = run("idle", IDLE_PROBE, "[]");
    assert!(check.status.success());
    assert!(!calls.contains("systemctl restart"), "{calls}");
}

#[test]
fn unfinished_probe_or_unreadable_fleet_refuses() {
    let (output, calls) = run("restart-user-manager", "@uid 1000\n", "[]");
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("cannot verify that gex45 is idle"));
    assert!(!calls.contains("systemctl restart"));
    let (output, _) = run("idle", IDLE_PROBE, "not json");
    assert_eq!(output.status.code(), Some(1));
}

const HOST_FLEET_PROBE: &str = "@uid 1000\n@fleet\n[\n{\"name\":\"sc-46-c\",\"status\":\"working\",\"machine\":null,\"parent\":null},\n{\"name\":\"sc-96q-judge\",\"status\":\"parked\",\"machine\":null,\"parent\":\"sc-96n-clip\"},\n{\"name\":\"sc-218-taps\",\"status\":\"idle\",\"machine\":\"gex45\",\"parent\":null},\n{\"name\":\"elsewhere\",\"status\":\"working\",\"machine\":\"nexus\",\"parent\":null},\n{\"name\":\"done\",\"status\":\"exited\",\"machine\":null,\"parent\":null}\n]\n\n@fleet-end\n@end\n";

#[test]
fn sessions_launched_on_the_host_refuse_whatever_their_parent() {
    let (output, calls) = run("restart-user-manager", HOST_FLEET_PROBE, FLEET);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(1), "{stderr}");
    for blocker in [
        "fleet session sc-46-c (working) on gex45",
        "fleet session sc-96q-judge (parked) on gex45",
        "fleet session sc-218-taps (working) on gex45",
        "fleet session sc-218-taps (idle) on gex45",
    ] {
        assert!(stderr.contains(blocker), "{blocker} missing from {stderr}");
    }
    assert!(
        !stderr.contains("elsewhere") && !stderr.contains("done"),
        "{stderr}"
    );
    assert!(!calls.contains("systemctl restart"), "{calls}");
    let (output, calls) = run(
        "restart-user-manager",
        "@uid 1000\n@fleet\nnot json\n@fleet-end\n@end\n",
        "[]",
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("north fleet list --json on gex45"));
    assert!(!calls.contains("systemctl restart"), "{calls}");
}
