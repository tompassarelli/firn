use super::ledger::{self, World};
use super::niri::{self, Window};
use super::Failure;
use serde_json::Value;
use std::collections::HashSet;
use std::path::PathBuf;

const FRAME: &str = "wm-mark";
const SUBJECT_PREFIX: &str = "@mark-";

pub struct Mark {
    pub letter: String,
    pub window: Option<u64>,
    pub app_id: Option<String>,
    pub title: Option<String>,
}

pub fn log_path() -> PathBuf {
    ledger::location("MARKS_LOG", "marks.jsonl")
}

pub fn mark(args: &[String]) -> Result<(), Failure> {
    let letter = letter(
        args.first(),
        "usage: wm-mark <letter> [id]  (letter = single alphanumeric)",
    )?;
    let window = match args.get(1) {
        Some(raw) => {
            let wanted = raw.parse::<u64>().ok();
            niri::windows()?
                .into_iter()
                .find(|window| Some(window.id) == wanted)
                .ok_or_else(|| Failure::new(1, format!("no window with id {raw}")))?
        }
        None => niri::focused_window()?.ok_or_else(|| Failure::new(1, "no focused window"))?,
    };
    set(&letter, &window)
}

pub fn set(letter: &str, window: &Window) -> Result<(), Failure> {
    let path = log_path();
    let subject = format!("{SUBJECT_PREFIX}{letter}");
    let text = |value: &Option<String>| value.as_deref().map_or(Value::Null, Value::from);
    let facts = [
        ("window", Value::from(format!("@w{}", window.id))),
        ("app_id", text(&window.app_id)),
        ("title", text(&window.title)),
        ("marked_at", Value::from(ledger::now_iso())),
    ];
    let first_tx = ledger::max_tx(&path) + 1;
    let lines: Vec<String> = facts
        .iter()
        .zip(first_tx..)
        .map(|((predicate, value), tx)| ledger::assertion(tx, &subject, predicate, value, FRAME))
        .collect();
    ledger::append(&path, &lines)?;
    println!(
        "marked {letter} -> @w{}  {}  {}",
        window.id,
        window.app_id.as_deref().unwrap_or(""),
        window.title.as_deref().unwrap_or("")
    );
    Ok(())
}

pub fn unmark(args: &[String]) -> Result<(), Failure> {
    let letter = letter(args.first(), "usage: wm-unmark <letter>")?;
    let path = log_path();
    let line = ledger::retraction(
        ledger::max_tx(&path) + 1,
        &format!("{SUBJECT_PREFIX}{letter}"),
        FRAME,
    );
    ledger::append(&path, &[line])?;
    println!("unmarked {letter}");
    Ok(())
}

pub fn list() -> Result<(), Failure> {
    let marks = read();
    if marks.is_empty() {
        println!("(no marks)");
        return Ok(());
    }
    let live = live_ids()?;
    for mark in marks {
        let state = if mark.window.is_some_and(|id| live.contains(&id)) {
            "alive"
        } else {
            "dead "
        };
        let id = mark.window.map_or("?".to_owned(), |id| id.to_string());
        println!(
            "{:<3} @w{:<5} {}  {:<24} {}",
            mark.letter,
            id,
            state,
            mark.app_id.as_deref().unwrap_or(""),
            mark.title.as_deref().unwrap_or("")
        );
    }
    Ok(())
}

pub fn jump(args: &[String]) -> Result<(), Failure> {
    let letter = letter(args.first(), "usage: wm-jump <letter>")?;
    let mark = read()
        .into_iter()
        .find(|mark| mark.letter == letter)
        .ok_or_else(|| Failure::new(1, format!("no mark {letter}")))?;
    let windows = niri::windows()?;
    let snapshot_app = mark.app_id.as_deref().unwrap_or("");
    if let Some(id) = mark.window.filter(|id| windows.iter().any(|w| w.id == *id)) {
        niri::focus(id);
        println!("exact -> @w{id}  {snapshot_app}");
        return Ok(());
    }
    let snapshot_title = mark.title.as_deref().unwrap_or("");
    let mut best: Option<(f64, &Window)> = None;
    for candidate in windows.iter().filter(|w| w.app_id == mark.app_id) {
        let score = similarity(snapshot_title, candidate.title.as_deref().unwrap_or(""));
        if best.is_none_or(|(top, _)| score >= top) {
            best = Some((score, candidate));
        }
    }
    let Some((_, window)) = best else {
        return Err(Failure::new(
            1,
            format!("unresolvable: mark {letter} -> {snapshot_app} (no live window of that app)"),
        ));
    };
    niri::focus(window.id);
    println!(
        "resolved-by-identity -> @w{}  {}  {}",
        window.id,
        window.app_id.as_deref().unwrap_or(""),
        window.title.as_deref().unwrap_or("")
    );
    Ok(())
}

pub fn read() -> Vec<Mark> {
    let world: World = ledger::fold(&log_path());
    world
        .into_iter()
        .filter_map(|(subject, facts)| {
            let letter = subject.strip_prefix(SUBJECT_PREFIX)?.to_owned();
            let text = |predicate: &str| facts.get(predicate)?.as_str().map(str::to_owned);
            Some(Mark {
                letter,
                window: text("window").and_then(|window| first_number(&window)),
                app_id: text("app_id"),
                title: text("title"),
            })
        })
        .collect()
}

pub fn live_ids() -> Result<HashSet<u64>, Failure> {
    Ok(niri::windows()?.iter().map(|window| window.id).collect())
}

fn letter(argument: Option<&String>, usage: &str) -> Result<String, Failure> {
    match argument {
        Some(text) if text.len() == 1 && text.as_bytes()[0].is_ascii_alphanumeric() => {
            Ok(text.to_ascii_lowercase())
        }
        _ => Err(Failure::usage(usage)),
    }
}

fn first_number(text: &str) -> Option<u64> {
    let digits: String = text
        .chars()
        .skip_while(|c| !c.is_ascii_digit())
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse().ok()
}

fn similarity(a: &str, b: &str) -> f64 {
    let a: Vec<char> = a.to_lowercase().chars().collect();
    let b: Vec<char> = b.to_lowercase().chars().collect();
    let longest = a.len().max(b.len());
    if longest == 0 {
        return 1.0;
    }
    1.0 - levenshtein(&a, &b) as f64 / longest as f64
}

fn levenshtein(a: &[char], b: &[char]) -> usize {
    let mut previous: Vec<usize> = (0..=b.len()).collect();
    for (i, left) in a.iter().enumerate() {
        let mut row = vec![i + 1];
        for (j, right) in b.iter().enumerate() {
            let cost = usize::from(left != right);
            row.push((row[j] + 1).min(previous[j + 1] + 1).min(previous[j] + cost));
        }
        previous = row;
    }
    previous[b.len()]
}
