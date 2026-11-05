use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

const LAND_UNIT: &str = "{\n  systemd.user.services.north-land.Service = {\n    ExecStart = \"${northBin}/north land serve --all --repo ${homeDir}/code/north/main\";\n  };\n}\n";

fn scratch() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("firn-unit-flags-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn runtime(dir: &Path, serve_help: &str) -> PathBuf {
    let path = dir.join("north");
    let body = format!(
        "#!/usr/bin/env bash\ncase \"$*\" in\n  'land serve --help') printf '%s\\n' '{serve_help}' ;;\n  'land --help') printf 'usage: north land serve|abandon\\n' ;;\n  *) echo \"error: unrecognized command\" >&2; exit 2 ;;\nesac\n"
    );
    fs::write(&path, body).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    path
}

fn check(unit: &str, serve_help: &str) -> Output {
    let dir = scratch();
    let repo = dir.join("config");
    fs::create_dir_all(repo.join("modules/north-land")).unwrap();
    fs::write(repo.join("modules/north-land/default.nix"), unit).unwrap();
    let north = runtime(&dir, serve_help);
    Command::new(env!("CARGO_BIN_EXE_firn-tools")).args(["unit-flags", "--repo"]).arg(&repo).arg("--north").arg(&north).output().unwrap()
}

fn text(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned() + &String::from_utf8_lossy(&output.stderr)
}

#[test]
fn a_unit_flag_the_runtime_help_lacks_is_refused() {
    let output = check(LAND_UNIT, "usage: north land serve --repo DIR [--once]");
    assert_eq!(output.status.code(), Some(1), "{}", text(&output));
    let report = text(&output);
    assert!(report.contains("modules/north-land/default.nix:3: `north land serve` is run with --all, which the installed runtime's `north land serve --help` does not list"), "{report}");
}

#[test]
fn a_unit_whose_flags_the_runtime_lists_passes() {
    let output = check(LAND_UNIT, "usage: north land serve --all --repo DIR");
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
}

#[test]
fn a_flag_that_only_prefixes_a_listed_flag_is_refused() {
    let output = check(LAND_UNIT, "usage: north land serve --allow-dirty --repo DIR");
    assert_eq!(output.status.code(), Some(1), "{}", text(&output));
}

#[test]
fn a_subcommand_the_runtime_lacks_is_refused() {
    let output = check("ExecStart = \"${northBin}/north lane-gc-tick --once\";\n", "usage");
    assert_eq!(output.status.code(), Some(1), "{}", text(&output));
    assert!(text(&output).contains("has no `north lane-gc-tick` subcommand"), "{}", text(&output));
}

#[test]
fn flags_after_the_command_separator_belong_to_the_wrapped_command() {
    let output = check("ExecStart = \"${northBin}/north land serve --all -- cargo build --release\";\n", "usage: north land serve --all");
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
}

#[test]
fn a_help_probe_that_runs_past_its_deadline_is_killed_and_named() {
    deadline_case("#!/usr/bin/env bash\nexec sleep 300\n");
}

#[test]
fn a_help_probe_whose_background_child_holds_its_output_open_is_killed_and_named() {
    deadline_case("#!/usr/bin/env bash\nsleep 300 &\nexit 0\n");
}

fn deadline_case(runtime: &str) {
    let dir = scratch();
    let repo = dir.join("config");
    fs::create_dir_all(repo.join("modules/watchdog")).unwrap();
    fs::write(repo.join("modules/watchdog/default.nix"), "ExecStart = \"${northBin}/north capacity watchdog sample --interval 5\";\n").unwrap();
    let north = dir.join("north");
    fs::write(&north, runtime).unwrap();
    fs::set_permissions(&north, fs::Permissions::from_mode(0o755)).unwrap();
    let started = std::time::Instant::now();
    let output = Command::new(env!("CARGO_BIN_EXE_firn-tools")).args(["unit-flags", "--repo"]).arg(&repo).arg("--north").arg(&north).output().unwrap();
    assert!(started.elapsed() < std::time::Duration::from_secs(20), "the probe ran {:?}", started.elapsed());
    assert_eq!(output.status.code(), Some(1), "{}", text(&output));
    assert!(text(&output).contains("modules/watchdog/default.nix:1: `north capacity watchdog sample --help` ran past 10 s and was killed"), "{}", text(&output));
}
