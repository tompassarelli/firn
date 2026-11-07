use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Desk {
    dir: PathBuf,
}

impl Desk {
    fn new(windows: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "firn-wm-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::SeqCst)
        ));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("windows.json"), windows).unwrap();
        let niri = dir.join("niri");
        fs::write(
            &niri,
            format!(
                "#!/usr/bin/env bash\ncase \"$*\" in\n*focus-window*) echo \"$*\" >>{focus}\n;;\n*'-j windows') cat {windows}\n;;\n*'-j focused-window') echo '{{\"id\":7,\"app_id\":\"ghostty\",\"title\":\"~/code\"}}'\n;;\nesac\n",
                focus = dir.join("focus.log").display(),
                windows = dir.join("windows.json").display()
            ),
        )
        .unwrap();
        fs::set_permissions(&niri, fs::Permissions::from_mode(0o755)).unwrap();
        Self { dir }
    }

    fn wm(&self, args: &[&str]) -> Output {
        let path = format!("{}:{}", self.dir.display(), std::env::var("PATH").unwrap());
        Command::new(env!("CARGO_BIN_EXE_firn-tools"))
            .arg("wm")
            .args(args)
            .env("PATH", path)
            .env("MARKS_LOG", self.marks())
            .output()
            .unwrap()
    }

    fn marks(&self) -> PathBuf {
        self.dir.join("marks.jsonl")
    }

    fn focused(&self) -> String {
        fs::read_to_string(self.dir.join("focus.log")).unwrap_or_default()
    }
}

impl Drop for Desk {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.dir).unwrap();
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
}

fn read_marks(path: &Path) -> Vec<serde_json::Value> {
    fs::read_to_string(path)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}

#[test]
fn mark_writes_four_assertions_and_lists_alive_then_dead_after_unmark() {
    let desk = Desk::new(r#"[{"id":7,"app_id":"ghostty","title":"~/code"}]"#);
    let marked = desk.wm(&["mark", "A"]);
    assert_eq!(stdout(&marked), "marked a -> @w7  ghostty  ~/code\n");

    let lines = read_marks(&desk.marks());
    let shape: Vec<(u64, &str, &str, &str, &str)> = lines
        .iter()
        .map(|line| {
            (
                line["tx"].as_u64().unwrap(),
                line["op"].as_str().unwrap(),
                line["l"].as_str().unwrap(),
                line["p"].as_str().unwrap(),
                line["frame"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        shape,
        [
            (1, "assert", "@mark-a", "window", "wm-mark"),
            (2, "assert", "@mark-a", "app_id", "wm-mark"),
            (3, "assert", "@mark-a", "title", "wm-mark"),
            (4, "assert", "@mark-a", "marked_at", "wm-mark"),
        ]
    );
    assert_eq!(lines[0]["r"], "@w7");
    assert!(lines[3]["ts"].as_str().unwrap().ends_with('Z'));

    assert_eq!(
        stdout(&desk.wm(&["marks"])),
        "a   @w7     alive  ghostty                  ~/code\n"
    );

    fs::write(desk.dir.join("windows.json"), "[]").unwrap();
    assert!(stdout(&desk.wm(&["marks"])).contains("dead "));

    assert_eq!(stdout(&desk.wm(&["unmark", "a"])), "unmarked a\n");
    assert_eq!(read_marks(&desk.marks()).last().unwrap()["op"], "retract");
    assert_eq!(stdout(&desk.wm(&["marks"])), "(no marks)\n");
}

#[test]
fn jump_focuses_the_marked_window_or_resolves_a_restarted_session_by_identity() {
    let desk = Desk::new(r#"[{"id":7,"app_id":"ghostty","title":"~/code"}]"#);
    desk.wm(&["mark", "a"]);
    assert_eq!(stdout(&desk.wm(&["jump", "a"])), "exact -> @w7  ghostty\n");
    assert!(desk.focused().contains("focus-window --id 7"));

    fs::write(
        desk.dir.join("windows.json"),
        r#"[{"id":3,"app_id":"foot","title":"~/code"},{"id":4,"app_id":"ghostty","title":"notes"},{"id":5,"app_id":"ghostty","title":"~/code/firn"}]"#,
    )
    .unwrap();
    assert_eq!(
        stdout(&desk.wm(&["jump", "a"])),
        "resolved-by-identity -> @w5  ghostty  ~/code/firn\n"
    );
    assert!(desk.focused().ends_with("focus-window --id 5\n"));

    fs::write(desk.dir.join("windows.json"), "[]").unwrap();
    let gone = desk.wm(&["jump", "a"]);
    assert_eq!(gone.status.code(), Some(1));
}
