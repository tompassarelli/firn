use std::fs;
use std::path::{Path, PathBuf};
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Sender};
use std::thread;
use std::time::{Duration, Instant};

const USAGE: &str = "usage: firn-tools unit-flags --repo DIR [--north PATH]";
const MARKER: &str = "${northBin}/north ";
const SKIPPED: [&str; 3] = [".git", "target", "node_modules"];
const DEADLINE: Duration = Duration::from_secs(10);

#[derive(Debug, PartialEq)]
pub struct Invocation {
    pub location: String,
    pub words: Vec<String>,
}

fn nix_sources(directory: &Path, found: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else { return };
    let mut paths: Vec<PathBuf> = entries.filter_map(|entry| entry.ok().map(|entry| entry.path())).collect();
    paths.sort();
    for path in paths {
        let name = path.file_name().and_then(|name| name.to_str()).unwrap_or_default();
        if path.is_dir() && !SKIPPED.contains(&name) {
            nix_sources(&path, found);
        } else if path.extension().is_some_and(|extension| extension == "nix") {
            found.push(path);
        }
    }
}

pub fn invocations(location: &str, text: &str) -> Vec<Invocation> {
    let mut found = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let mut from = 0;
        while let Some(at) = line[from..].find(MARKER) {
            let rest = &line[from + at + MARKER.len()..];
            from += at + MARKER.len();
            let mut words = Vec::new();
            for word in rest.split_whitespace() {
                let closes = word.ends_with(['"', ';']);
                let word = word.trim_end_matches(['"', ';']);
                if !word.is_empty() {
                    words.push(word.to_owned());
                }
                if closes {
                    break;
                }
            }
            if !words.is_empty() {
                found.push(Invocation { location: format!("{location}:{}", index + 1), words });
            }
        }
    }
    found
}

fn names_flag(help: &str, flag: &str) -> bool {
    help.match_indices(flag).any(|(at, _)| {
        let before = help[..at].chars().next_back();
        let after = help[at + flag.len()..].chars().next();
        !before.is_some_and(|c| c.is_alphanumeric() || c == '-') && !after.is_some_and(|c| c.is_alphanumeric() || c == '-' || c == '_')
    })
}

fn drain(mut pipe: impl Read + Send + 'static, sent: Sender<String>) {
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = pipe.read_to_end(&mut bytes);
        let _ = sent.send(String::from_utf8_lossy(&bytes).into_owned());
    });
}

fn help(north: &Path, path: &[&str]) -> Result<Option<String>, String> {
    let Ok(mut child) = Command::new(north).args(path).arg("--help").stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0).spawn() else {
        return Ok(None);
    };
    let (sent, received) = mpsc::channel();
    let (Some(stdout), Some(stderr)) = (child.stdout.take(), child.stderr.take()) else { return Ok(None) };
    drain(stdout, sent.clone());
    drain(stderr, sent);
    let started = Instant::now();
    let mut status = None;
    let mut text = String::new();
    let mut closed = 0;
    while status.is_none() || closed < 2 {
        if started.elapsed() >= DEADLINE {
            let _ = Command::new("kill").args(["-KILL", "--", &format!("-{}", child.id())]).stderr(Stdio::null()).status();
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!("`north {} --help` ran past {} s and was killed: the installed runtime runs that verb instead of printing its usage", path.join(" "), DEADLINE.as_secs()));
        }
        if status.is_none() {
            status = child.try_wait().ok().flatten();
        }
        if let Ok(output) = received.recv_timeout(Duration::from_millis(20)) {
            text.push_str(&output);
            closed += 1;
        }
    }
    Ok(status.is_some_and(|status| status.success()).then_some(text))
}

pub fn problems(invocation: &Invocation, mut ask: impl FnMut(&[&str]) -> Result<Option<String>, String>) -> Vec<String> {
    let leading: Vec<&str> = invocation.words.iter().map(String::as_str).take_while(|word| !word.starts_with('-')).collect();
    let flags: Vec<&str> = invocation.words.iter().map(String::as_str).take_while(|word| *word != "--").filter(|word| word.starts_with("--")).map(|word| word.split('=').next().unwrap_or(word)).collect();
    let Some(first) = leading.first() else { return Vec::new() };
    let mut answered = None;
    for length in (1..=leading.len()).rev() {
        match ask(&leading[..length]) {
            Ok(Some(text)) => {
                answered = Some((length, text));
                break;
            }
            Ok(None) => {}
            Err(killed) => return vec![format!("{}: {killed}", invocation.location)],
        }
    }
    let Some((length, help)) = answered else {
        return vec![format!("{}: the installed north runtime has no `north {first}` subcommand", invocation.location)];
    };
    let command = leading[..length].join(" ");
    flags
        .into_iter()
        .filter(|flag| !names_flag(&help, flag))
        .map(|flag| format!("{}: `north {command}` is run with {flag}, which the installed runtime's `north {command} --help` does not list", invocation.location))
        .collect()
}

fn fail(message: &str, code: i32) -> ! {
    eprintln!("{message}");
    std::process::exit(code)
}

pub fn run() {
    let mut repo = None;
    let mut north = None;
    let mut arguments = std::env::args().skip(2);
    while let Some(flag) = arguments.next() {
        let Some(value) = arguments.next() else { fail(USAGE, 64) };
        match flag.as_str() {
            "--repo" => repo = Some(PathBuf::from(value)),
            "--north" => north = Some(PathBuf::from(value)),
            _ => fail(USAGE, 64),
        }
    }
    let Some(repo) = repo else { fail(USAGE, 64) };
    let north = north.or_else(runtime_north);
    let Some(north) = north.filter(|path| path.is_file()) else {
        println!("firn check: ⚠ no north runtime found, so units' north subcommands and flags were not checked against its --help.");
        return;
    };
    let mut sources = Vec::new();
    nix_sources(&repo, &mut sources);
    let mut refused = Vec::new();
    for source in sources {
        let Ok(text) = fs::read_to_string(&source) else { continue };
        let location = source.strip_prefix(&repo).unwrap_or(&source).display().to_string();
        for invocation in invocations(&location, &text) {
            refused.extend(problems(&invocation, |path| help(&north, path)));
        }
    }
    if refused.is_empty() {
        println!("firn check: units' north subcommands and flags match the installed runtime");
        return;
    }
    refused.iter().for_each(|line| println!("firn check: ✗ {line}"));
    println!("firn check: a unit that runs a flag the installed runtime lacks crash-loops on the next switch; land the north change and update the runtime first, or drop the flag from the unit.");
    std::process::exit(1);
}

fn runtime_north() -> Option<PathBuf> {
    std::env::var_os("FIRN_UNIT_NORTH").map(PathBuf::from).or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/bin/north")))
}
