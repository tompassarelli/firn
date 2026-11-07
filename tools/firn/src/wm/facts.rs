use super::ledger;
use super::Failure;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::time::Duration;

const FRAME: &str = "wm";
const TERMINAL_APPS: [&str; 3] = ["ghostty", "Alacritty", "foot"];
const STABLE_PREDICATES: [&str; 3] = ["app_id", "title", "workspace"];

fn log_path() -> PathBuf {
    ledger::location("WM_FACTS_LOG", "facts.jsonl")
}

pub fn query(args: &[String]) -> Result<(), Failure> {
    if args.first().map(String::as_str) != Some("recent-terminal") {
        return Err(Failure::usage("usage: wm-query recent-terminal"));
    }
    let latest = ledger::fold(&log_path())
        .into_iter()
        .filter_map(|(subject, facts)| {
            let app = facts.get("app_id")?.as_str()?;
            let focused = facts.get("focused_at")?.as_str()?.to_owned();
            let open = facts.get("closed_at").is_none_or(Value::is_null);
            let terminal = TERMINAL_APPS.iter().any(|mark| app.contains(mark));
            let title = facts.get("title").and_then(Value::as_str).unwrap_or("");
            (terminal && open).then(|| (focused, subject, title.to_owned()))
        })
        .max_by(|a, b| a.0.cmp(&b.0));
    match latest {
        Some((_, subject, title)) => {
            println!("{}\t{title}", subject.trim_start_matches('@'));
            Ok(())
        }
        None => Err(Failure::new(1, "no terminal window found")),
    }
}

struct Writer {
    path: PathBuf,
    tx: u64,
    known: HashSet<String>,
    last: HashMap<(String, String), Value>,
}

impl Writer {
    fn primed(path: PathBuf) -> Self {
        let mut writer = Self {
            tx: 0,
            known: HashSet::new(),
            last: HashMap::new(),
            path,
        };
        for record in ledger::records(&writer.path) {
            if let Some(tx) = record["tx"].as_u64() {
                writer.tx = writer.tx.max(tx);
            }
            let (Some(subject), Some(predicate)) = (record["l"].as_str(), record["p"].as_str())
            else {
                continue;
            };
            if predicate == "opened_at" {
                writer.known.insert(subject.to_owned());
            }
            if STABLE_PREDICATES.contains(&predicate) {
                writer
                    .last
                    .insert((subject.to_owned(), predicate.to_owned()), record["r"].clone());
            }
        }
        writer
    }

    fn emit(&mut self, subject: &str, predicate: &str, value: Value) {
        self.tx += 1;
        let line = ledger::assertion(self.tx, subject, predicate, &value, FRAME);
        if let Err(error) = ledger::append(&self.path, &[line]) {
            eprintln!("event error: {error}");
        }
    }

    fn stamp(&mut self, subject: &str, predicate: &str) {
        self.emit(subject, predicate, Value::from(ledger::now_iso()));
    }

    fn emit_changed(&mut self, subject: &str, predicate: &str, value: &Value) {
        let key = (subject.to_owned(), predicate.to_owned());
        if self.last.get(&key) != Some(value) {
            self.last.insert(key, value.clone());
            self.emit(subject, predicate, value.clone());
        }
    }

    fn window(&mut self, window: &Value) {
        let subject = subject(&window["id"]);
        for (field, predicate) in [
            ("app_id", "app_id"),
            ("title", "title"),
            ("workspace_id", "workspace"),
        ] {
            if !window[field].is_null() {
                self.emit_changed(&subject, predicate, &window[field]);
            }
        }
        if self.known.insert(subject.clone()) {
            self.stamp(&subject, "opened_at");
        }
        if window["is_focused"] == Value::Bool(true) {
            self.stamp(&subject, "focused_at");
        }
    }

    fn event(&mut self, event: &Value) {
        let Some((name, body)) = event.as_object().and_then(|map| map.iter().next()) else {
            return;
        };
        match name.as_str() {
            "WindowsChanged" => {
                for window in body["windows"].as_array().into_iter().flatten() {
                    self.window(window);
                }
            }
            "WindowOpenedOrChanged" => self.window(&body["window"]),
            "WindowClosed" => self.stamp(&subject(&body["id"]), "closed_at"),
            "WindowFocusChanged" if !body["id"].is_null() => {
                self.stamp(&subject(&body["id"]), "focused_at");
            }
            _ => {}
        }
    }
}

fn subject(id: &Value) -> String {
    match id {
        Value::Null => "@w".to_owned(),
        other => format!("@w{other}"),
    }
}

pub fn daemon() -> Result<(), Failure> {
    let path = log_path();
    let mut writer = Writer::primed(path.clone());
    eprintln!(
        "wm-facts-daemon started; log = {} tx = {}",
        path.display(),
        writer.tx
    );
    loop {
        match super::niri::event_stream() {
            Ok(mut child) => {
                if let Some(stdout) = child.stdout.take() {
                    for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                        if line.trim().is_empty() {
                            continue;
                        }
                        match serde_json::from_str(&line) {
                            Ok(event) => writer.event(&event),
                            Err(error) => eprintln!("event error: {error}"),
                        }
                    }
                }
                let _ = child.wait();
            }
            Err(error) => eprintln!("stream error: {error}"),
        }
        eprintln!("niri stream ended; reconnecting in 2s");
        std::thread::sleep(Duration::from_secs(2));
    }
}
