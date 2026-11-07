use super::marks;
use super::niri;
use super::Failure;
use std::io::Write;
use std::process::{Command, Stdio};

pub fn mark() -> Result<(), Failure> {
    let Some(window) = niri::focused_window()? else {
        run_rofi(&["-e", "no focused window to mark"], "")?;
        return Err(Failure::new(1, "no focused window"));
    };
    let prompt = format!("set mark for: {}", window.app_id.as_deref().unwrap_or(""));
    let selection = run_rofi(&["-dmenu", "-p", &prompt], "")?;
    let letter = selection.trim();
    if letter.len() == 1 && letter.as_bytes()[0].is_ascii_alphanumeric() {
        marks::set(&letter.to_ascii_lowercase(), &window)?;
    }
    Ok(())
}

pub fn jump() -> Result<(), Failure> {
    let all = marks::read();
    if all.is_empty() {
        run_rofi(&["-e", "no marks set"], "")?;
        return Ok(());
    }
    let live = marks::live_ids()?;
    let rows: Vec<String> = all
        .iter()
        .map(|mark| {
            let alive = if mark.window.is_some_and(|id| live.contains(&id)) {
                "●"
            } else {
                "○"
            };
            format!(
                "{}  {alive}  {} — {}",
                mark.letter,
                mark.app_id.as_deref().unwrap_or(""),
                mark.title.as_deref().unwrap_or("")
            )
        })
        .collect();
    let selection = run_rofi(&["-dmenu", "-i", "-p", "jump to mark"], &rows.join("\n"))?;
    match selection.split_whitespace().next() {
        Some(letter) => marks::jump(&[letter.to_owned()]),
        None => Ok(()),
    }
}

fn run_rofi(args: &[&str], input: &str) -> Result<String, Failure> {
    let mut child = Command::new("rofi")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("rofi: {error}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }
    let output = child
        .wait_with_output()
        .map_err(|error| format!("rofi: {error}"))?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}
