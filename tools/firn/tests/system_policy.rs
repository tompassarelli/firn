use serde_json::json;
use std::fs;
use std::io::Write;
use std::os::unix::fs::symlink;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const REASON: &str = "BLOCKED: raw nixos-rebuild/darwin-rebuild/nh bypasses the sanctioned snapshot workflow. Use `firn rebuild` after the relevant checks pass and owned changes are committed.";
const DIGEST: &str = concat!(
    "You are editing the Firn NixOS configuration. Edit idiomatic Nix modules ",
    "and source-owned JSON tag metadata; run firn check after changes. ",
    "Inspect option schemas with firn schema explain. ",
    "Keep Tom-maintained and high-churn project source and build outputs out ",
    "of the boot/system closure. A derivation, package, worktree, or filesystem ",
    "pin does not grant closure admission; use a dev shell, user runtime, or ",
    "direct out-of-store launcher unless an exact stable machine/service ",
    "responsibility is declared. ",
    "Use firn's committed-snapshot workflow for system changes; raw ",
    "nixos-rebuild, darwin-rebuild, and nh switching are forbidden. ",
    "Secrets use sops-nix only."
);
static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Hook {
    root: PathBuf,
    override_value: Option<String>,
    fallback: bool,
}

impl Hook {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "firn-policy-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        for directory in [
            "actual",
            "reference",
            "state/current",
            "home/.local/state/north/agents/current",
            "checkout/code/nixos-config/native",
        ] {
            fs::create_dir_all(root.join(directory)).unwrap();
        }
        fs::write(
            root.join("checkout/code/nixos-config/native/module.nix"),
            "",
        )
        .unwrap();
        symlink(root.join("checkout/code/nixos-config"), root.join("alias")).unwrap();
        let hook = Self {
            root,
            override_value: None,
            fallback: false,
        };
        hook.activation(true, "north.agent-activation/v1", "on");
        hook
    }

    fn activation(&self, active: bool, schema: &str, permission: &str) {
        self.activation_text(&json!({"schema":schema,"catalogDigest":"sha256:a","generationId":"sha256:b",
            "units":[{"id":"firn-system-policy","kind":"hook","permission":permission,"active":active}]}).to_string());
    }

    fn activation_text(&self, text: &str) {
        for path in [
            "state/current/activation.json",
            "home/.local/state/north/agents/current/activation.json",
        ] {
            fs::write(self.root.join(path), text).unwrap();
        }
    }

    fn run(&self, payload: &[u8], expected: &str) {
        let invoke = |reference: bool| {
            let mut command = if reference {
                Command::new(std::env::var_os("FIRN_POLICY_REFERENCE").unwrap())
            } else {
                let mut command = Command::new(env!("CARGO_BIN_EXE_firn-tools"));
                command.arg("system-policy");
                command
            };
            command
                .env("HOME", self.root.join("home"))
                .env(
                    "XDG_RUNTIME_DIR",
                    self.root
                        .join(if reference { "reference" } else { "actual" }),
                )
                .env_remove("AGENT_NO_AUTHORING_HOOKS")
                .env_remove("NORTH_AGENT_STATE_ROOT");
            if !self.fallback {
                command.env("NORTH_AGENT_STATE_ROOT", self.root.join("state"));
            }
            if let Some(value) = &self.override_value {
                command.env("AGENT_NO_AUTHORING_HOOKS", value);
            }
            let mut child = command
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .unwrap();
            let _ = child.stdin.take().unwrap().write_all(payload);
            child.wait_with_output().unwrap()
        };
        let actual = invoke(false);
        assert_eq!(actual.status.code(), Some(0));
        assert!(actual.stderr.is_empty(), "{:?}", actual.stderr);
        assert_eq!(String::from_utf8_lossy(&actual.stdout), expected);
        if std::env::var_os("FIRN_POLICY_REFERENCE").is_some() {
            let reference = invoke(true);
            assert_eq!(actual.status.code(), reference.status.code());
            assert_eq!(actual.stdout, reference.stdout, "TS vs Rust stdout");
            assert_eq!(actual.stderr, reference.stderr, "TS vs Rust stderr");
            let markers = |directory| {
                let mut names: Vec<_> = fs::read_dir(self.root.join(directory))
                    .unwrap()
                    .map(|entry| entry.unwrap().file_name())
                    .collect();
                names.sort();
                names
            };
            assert_eq!(
                markers("actual"),
                markers("reference"),
                "TS vs Rust session markers"
            );
        }
    }

    fn bash(&self, command: &str, deny: bool) {
        self.run(
            json!({"tool_name":"Bash","tool_input":{"command":command},"session_id":"session"})
                .to_string()
                .as_bytes(),
            &output(deny, !deny),
        );
    }
}

impl Drop for Hook {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.root).unwrap();
    }
}

fn output(deny: bool, pass: bool) -> String {
    if pass {
        return String::new();
    }
    if deny {
        format!(
            "{{\"hookSpecificOutput\":{{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":{}}}}}\n",
            serde_json::to_string(REASON).unwrap()
        )
    } else {
        format!(
            "{{\"hookSpecificOutput\":{{\"hookEventName\":\"PreToolUse\",\"additionalContext\":{}}}}}\n",
            serde_json::to_string(DIGEST).unwrap()
        )
    }
}

macro_rules! bash_cases {
    ($($name:ident: $command:expr => $deny:expr),* $(,)?) => { $(
        #[test]
        fn $name() { Hook::new().bash($command, $deny); }
    )* };
}
bash_cases! {
    sanctioned_rebuild_passes: "firn rebuild" => false,
    sanctioned_upgrade_passes: "firn repo upgrade now" => false,
    echo_is_not_a_rebuild: "echo nixos-rebuild switch" => false,
    sudo_test_is_denied: "sudo nixos-rebuild test" => true,
    raw_switch_is_denied: "nixos-rebuild switch" => true,
    raw_boot_is_denied: "doas nixos-rebuild --flake . boot" => true,
    darwin_switch_is_denied: "darwin-rebuild switch" => true,
    darwin_boot_is_denied: "darwin-rebuild boot" => true,
    darwin_test_passes: "darwin-rebuild test" => false,
    nh_switch_is_denied: "nh switch" => true,
    nh_boot_is_denied: "nh boot" => true,
    nh_os_switch_is_denied: "sudo nh os switch" => true,
    nh_os_boot_is_denied: "nh os boot" => true,
    nh_build_passes: "nh os build" => false,
    command_chain_is_denied: "true; nixos-rebuild switch" => true,
    substitution_is_denied: "echo $(nixos-rebuild switch)" => true,
    backtick_is_denied: "echo `nh os boot`" => true,
    adjacent_name_passes: "nixos-rebuild-extra switch" => false,
    absolute_path_preserves_current_verdict: "/bin/nixos-rebuild switch" => false,
    option_after_operation_preserves_current_verdict: "nh --verbose os switch" => false,
}

#[test]
fn edit_introduction_resolves_symlinks_and_is_once_per_session() {
    let hook = Hook::new();
    let payload = json!({"tool_name":"Edit","tool_input":{"file_path":hook.root.join("alias/native/module.nix")},"session_id":"inject/session"}).to_string();
    hook.run(payload.as_bytes(), &output(false, false));
    assert!(
        hook.root
            .join("actual/firn-system-policy.inject_session")
            .is_file()
    );
    hook.run(payload.as_bytes(), "");
}

macro_rules! edit_cases {
    ($($name:ident: $tool:expr, $field:expr),* $(,)?) => { $(
        #[test]
        fn $name() {
            let hook = Hook::new();
            hook.run(json!({"tool_name":$tool,"tool_input":{$field:hook.root.join("alias/native/module.nix")},"session_id":stringify!($name)}).to_string().as_bytes(), &output(false, false));
        }
    )* };
}
edit_cases! {
    write_accepts_camel_case_path: "Write", "filePath",
    multiedit_injects_context: "MultiEdit", "file_path",
}

#[test]
fn unrelated_paths_and_undecodable_patch_pass() {
    let hook = Hook::new();
    for payload in [
        r#"{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch"},"session_id":"apply-patch"}"#,
        r#"{"tool_name":"Edit","tool_input":{"file_path":"/tmp/other/module.nix"}}"#,
    ] {
        hook.run(payload.as_bytes(), "");
    }
}

macro_rules! activation_cases {
    ($($name:ident: $active:expr, $schema:expr, $permission:expr),* $(,)?) => { $(
        #[test]
        fn $name() {
            let hook = Hook::new();
            hook.activation($active, $schema, $permission);
            hook.bash("nixos-rebuild switch", false);
        }
    )* };
}
activation_cases! {
    inactive_hook_passes: false, "north.agent-activation/v1", "off",
    invalid_activation_passes: true, "north.agent-activation/invalid", "on",
    ttl_permission_passes: true, "north.agent-activation/v1", "off:until=2099-01-01T00:00:00Z",
    off_permission_with_active_flag_passes: true, "north.agent-activation/v1", "off",
}

#[test]
fn override_zero_and_false_force_live_even_when_inactive() {
    let mut hook = Hook::new();
    hook.activation(false, "north.agent-activation/v1", "off");
    for value in ["0", "false"] {
        hook.override_value = Some(value.into());
        hook.bash("nixos-rebuild switch", true);
    }
}

#[test]
fn nonempty_override_disables_hook() {
    let mut hook = Hook::new();
    for value in ["1", "true", "FALSE"] {
        hook.override_value = Some(value.into());
        hook.bash("nixos-rebuild switch", false);
    }
}

#[test]
fn missing_malformed_or_duplicate_activation_passes() {
    let hook = Hook::new();
    fs::remove_file(hook.root.join("state/current/activation.json")).unwrap();
    hook.bash("nixos-rebuild switch", false);
    for text in [
        "{",
        "{}",
        r#"{"schema":"north.agent-activation/v1","catalogDigest":"a","generationId":"b","units":[{"kind":"hook","id":"firn-system-policy","active":true,"permission":"on"},{"kind":"hook","id":"firn-system-policy","active":true,"permission":"on"}]}"#,
    ] {
        hook.activation_text(text);
        hook.bash("nixos-rebuild switch", false);
    }
}

#[test]
fn home_activation_fallback_is_used() {
    let mut hook = Hook::new();
    hook.fallback = true;
    hook.bash("nixos-rebuild switch", true);
}

#[test]
fn malformed_and_oversized_payloads_pass_silently() {
    let hook = Hook::new();
    for payload in [
        b"{not-json".as_slice(),
        b"[]",
        b"null",
        b"{} {}",
        br#"{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"extra":"\ud800"}"#,
    ] {
        hook.run(payload, "");
    }
    hook.run(&vec![b'x'; 1_048_577], "");
}

#[test]
fn duplicate_fields_use_the_first_value() {
    let hook = Hook::new();
    hook.run(br#"{"tool_name":"Bash","tool_name":"Edit","tool_input":{"command":"nixos-rebuild switch","command":"echo ok"}}"#, &output(true, false));
}

#[test]
fn bom_and_large_unused_numbers_preserve_decisions() {
    let hook = Hook::new();
    hook.run("\u{feff}{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"nixos-rebuild switch\"},\"unused\":1e9999}".as_bytes(), &output(true, false));
    hook.run(
        "{\"tool_name\":\"\u{feff}Bash\",\"tool_input\":{\"command\":\"nixos-rebuild switch\"}}"
            .as_bytes(),
        "",
    );
}
