use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

const USAGE: &str = "usage: firn-tools profile replace NAME INSTALLABLE [NIX_ARGS...]";

pub fn run() {
    let args: Vec<String> = std::env::args().skip(2).collect();
    let [verb, name, installable, extra @ ..] = args.as_slice() else {
        fail(USAGE, 64)
    };
    if verb != "replace" {
        fail(USAGE, 64);
    }
    match replace(&profile(), name, installable, extra) {
        Ok(paths) => paths.iter().for_each(|path| println!("{path}")),
        Err(error) => fail(&format!("firn-tools profile replace: {error}"), 1),
    }
}

fn fail(message: &str, code: i32) -> ! {
    eprintln!("{message}");
    std::process::exit(code)
}

/// The profile `~/.nix-profile` names, which `nix profile` writes by default.
fn profile() -> PathBuf {
    let link = PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".nix-profile");
    match std::fs::read_link(&link) {
        Ok(target) if target.is_absolute() => target,
        Ok(target) => link.parent().unwrap_or(Path::new("/")).join(target),
        Err(_) => link,
    }
}

/// Replaces the element `name` of `profile` with `installable` in one new generation: the remove and the add run on a scratch copy of the current generation, and the profile moves to the result in one `nix-env --set`, so no generation it passes through lacks the element.
fn replace(
    profile: &Path,
    name: &str,
    installable: &str,
    extra: &[String],
) -> Result<Vec<String>, String> {
    let scratch = Scratch::new()?;
    let copy = scratch.0.join("profile");
    let copy_arg = copy.display().to_string();
    if let Ok(current) = std::fs::canonicalize(profile) {
        nix_env(&copy, &current)?;
        if elements(&copy_arg)?.get(name).is_some() {
            call("nix", &["profile", "remove", "--profile", &copy_arg, name])?;
        }
    }
    let mut add = vec!["profile", "add", "--profile", &copy_arg, installable];
    add.extend(extra.iter().map(String::as_str));
    call("nix", &add)?;
    let built = std::fs::canonicalize(&copy).map_err(|error| format!("{copy_arg}: {error}"))?;
    nix_env(profile, &built)?;
    let listed = elements(&profile.display().to_string())?;
    Ok(listed
        .get(name)
        .and_then(|element| element["storePaths"].as_array())
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect())
}

fn nix_env(profile: &Path, generation: &Path) -> Result<(), String> {
    call(
        "nix-env",
        &[
            "--profile",
            &profile.display().to_string(),
            "--set",
            &generation.display().to_string(),
        ],
    )
}

fn elements(profile: &str) -> Result<serde_json::Map<String, Value>, String> {
    let output = Command::new("nix")
        .args(["profile", "list", "--json", "--profile", profile])
        .output()
        .map_err(|error| format!("nix: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "nix profile list --profile {profile} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let listed: Value = serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("nix profile list --profile {profile}: {error}"))?;
    Ok(listed["elements"].as_object().cloned().unwrap_or_default())
}

fn call(program: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|error| format!("{program}: {error}"))?;
    status
        .success()
        .then_some(())
        .ok_or_else(|| format!("{program} {} failed: {status}", args.join(" ")))
}

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Result<Self, String> {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |since| since.as_nanos());
        let dir = std::env::temp_dir().join(format!("firn-profile-{}-{nanos}", std::process::id()));
        std::fs::create_dir(&dir).map_err(|error| format!("{}: {error}", dir.display()))?;
        Ok(Self(dir))
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
