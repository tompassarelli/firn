use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::Path;
use std::process::Command;

const NEW_GENERATION: &str = r#"newgen() {
  n=$(cat "$S/counter" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$S/counter"
  g="$S/gen-$n"; mkdir -p "$g"; cat >"$g/elements"
  ln -sfn "$g" "$1"; printf '%s %s\n' "$1" "$g" >>"$S/log"
}"#;

const NIX_ENV: &str = r#"[ "$1" = --profile ] && [ "$3" = --set ] || exit 2
cat "$4/elements" | newgen "$2""#;

const NIX: &str = r#"case "$1 $2" in
  "profile list") p="$5"; printf '{"elements":{'; sep=; while IFS="$(printf '\t')" read -r name path; do printf '%s"%s":{"storePaths":["%s"]}' "$sep" "$name" "$path"; sep=,; done <"$p/elements"; printf '}}\n' ;;
  "profile remove") grep -v "^$5	" "$4/elements" | newgen "$4" ;;
  "profile add") env="$S/env-new"; mkdir -p "$env/bin"; touch "$env/bin/git"; { cat "$4/elements" 2>/dev/null; printf '%s\t%s\n' "${5##*#}" "$env"; } | newgen "$4" ;;
  *) exit 2 ;;
esac"#;

fn tool(dir: &Path, name: &str, store: &Path, body: &str) {
    let path = dir.join(name);
    fs::write(
        &path,
        format!(
            "#!/usr/bin/env bash\nS={}\n{NEW_GENERATION}\n{body}\n",
            store.display()
        ),
    )
    .unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn has_git(generation: &Path) -> bool {
    fs::read_to_string(generation.join("elements"))
        .unwrap()
        .lines()
        .filter_map(|line| line.split_once('\t'))
        .any(|(_, path)| Path::new(path).join("bin/git").exists())
}

#[test]
fn a_profile_switch_moves_the_profile_once_and_never_through_a_generation_without_git() {
    let root = std::env::temp_dir().join(format!("firn-profile-test-{}", std::process::id()));
    let (bin, store, home) = (root.join("bin"), root.join("store"), root.join("home"));
    for dir in [&bin, &store, &home, &root.join("profiles")] {
        fs::create_dir_all(dir).unwrap();
    }
    let old = store.join("env-old");
    fs::create_dir_all(old.join("bin")).unwrap();
    fs::write(old.join("bin/git"), "").unwrap();
    let first = store.join("gen-0");
    fs::create_dir_all(&first).unwrap();
    fs::write(
        first.join("elements"),
        format!("whiterabbit-environment\t{}\n", old.display()),
    )
    .unwrap();
    let profile = root.join("profiles/profile");
    symlink(&first, &profile).unwrap();
    symlink(&profile, home.join(".nix-profile")).unwrap();
    tool(&bin, "nix", &store, NIX);
    tool(&bin, "nix-env", &store, NIX_ENV);

    let output = Command::new(env!("CARGO_BIN_EXE_firn-tools"))
        .args([
            "profile",
            "replace",
            "whiterabbit-environment",
            "path:/flake#whiterabbit-environment",
        ])
        .env(
            "PATH",
            format!("{}:{}", bin.display(), std::env::var("PATH").unwrap()),
        )
        .env("HOME", &home)
        .output()
        .unwrap();

    let log = fs::read_to_string(store.join("log")).unwrap_or_default();
    let switched: Vec<&str> = log
        .lines()
        .filter_map(|line| line.strip_prefix(&format!("{} ", profile.display())))
        .collect();
    let printed = String::from_utf8_lossy(&output.stdout).into_owned();
    let without_git: Vec<&&str> = switched
        .iter()
        .filter(|generation| !has_git(Path::new(generation)))
        .collect();
    fs::remove_dir_all(&root).unwrap_or_default();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        switched.len(),
        1,
        "on 2026-11-08 ~/.nix-profile went 1272 -> 1273 (no git) -> 1274 in one switch: {log}"
    );
    assert!(
        log.lines().count() > 1,
        "the remove and the add ran on the scratch copy: {log}"
    );
    assert_eq!(printed.trim(), store.join("env-new").display().to_string());
    assert!(
        without_git.is_empty(),
        "the profile passed through {without_git:?}"
    );
}
