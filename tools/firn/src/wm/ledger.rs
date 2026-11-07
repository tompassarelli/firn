use serde_json::Value;
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub type World = BTreeMap<String, BTreeMap<String, Value>>;

pub fn location(variable: &str, file: &str) -> PathBuf {
    match std::env::var_os(variable) {
        Some(path) => path.into(),
        None => {
            let home = std::env::var_os("HOME").unwrap_or_default();
            Path::new(&home).join(".local/state/wm-world").join(file)
        }
    }
}

pub fn assertion(tx: u64, subject: &str, predicate: &str, value: &Value, frame: &str) -> String {
    format!(
        r#"{{"tx":{tx},"op":"assert","l":{},"p":{},"r":{value},"frame":{},"ts":{}}}"#,
        quote(subject),
        quote(predicate),
        quote(frame),
        quote(&now_iso())
    )
}

pub fn retraction(tx: u64, subject: &str, frame: &str) -> String {
    format!(
        r#"{{"tx":{tx},"op":"retract","l":{},"frame":{},"ts":{}}}"#,
        quote(subject),
        quote(frame),
        quote(&now_iso())
    )
}

fn quote(text: &str) -> String {
    Value::from(text).to_string()
}

pub fn append(path: &Path, lines: &[String]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("{}: {error}", parent.display()))?;
    }
    let mut text = lines.join("\n");
    text.push('\n');
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .and_then(|mut file| file.write_all(text.as_bytes()))
        .map_err(|error| format!("{}: {error}", path.display()))
}

pub fn records(path: &Path) -> Vec<Value> {
    let Ok(bytes) = fs::read(path) else {
        return Vec::new();
    };
    String::from_utf8_lossy(&bytes)
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

pub fn max_tx(path: &Path) -> u64 {
    records(path)
        .iter()
        .filter_map(|record| record["tx"].as_u64())
        .max()
        .unwrap_or(0)
}

pub fn fold(path: &Path) -> World {
    let mut world = World::new();
    for record in records(path) {
        let Some(subject) = record["l"].as_str() else {
            continue;
        };
        let predicate = record["p"].as_str();
        match (record["op"].as_str(), predicate) {
            (Some("retract"), Some(predicate)) => {
                if let Some(facts) = world.get_mut(subject) {
                    facts.remove(predicate);
                }
            }
            (Some("retract"), None) => {
                world.remove(subject);
            }
            (Some("assert"), Some(predicate)) => {
                world
                    .entry(subject.to_owned())
                    .or_default()
                    .insert(predicate.to_owned(), record["r"].clone());
            }
            _ => {}
        }
    }
    world
}

pub fn now_iso() -> String {
    let since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format_instant(since_epoch.as_secs() as i64, since_epoch.subsec_nanos())
}

fn format_instant(seconds: i64, nanos: u32) -> String {
    let (year, month, day) = civil_date(seconds.div_euclid(86_400));
    let in_day = seconds.rem_euclid(86_400);
    let mut text = format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}",
        in_day / 3600,
        in_day % 3600 / 60,
        in_day % 60
    );
    match nanos {
        0 => {}
        n if n.is_multiple_of(1_000_000) => text.push_str(&format!(".{:03}", n / 1_000_000)),
        n if n.is_multiple_of(1000) => text.push_str(&format!(".{:06}", n / 1000)),
        n => text.push_str(&format!(".{n:09}")),
    }
    text.push('Z');
    text
}

fn civil_date(days: i64) -> (i64, i64, i64) {
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 {
        month_index + 3
    } else {
        month_index - 9
    };
    (
        year_of_era + era * 400 + i64::from(month <= 2),
        month,
        day,
    )
}
