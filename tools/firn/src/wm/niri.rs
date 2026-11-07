use serde_json::Value;
use std::process::{Child, Command, Stdio};

pub struct Window {
    pub id: u64,
    pub app_id: Option<String>,
    pub title: Option<String>,
}

impl Window {
    fn from_value(value: &Value) -> Option<Self> {
        Some(Self {
            id: value["id"].as_u64()?,
            app_id: value["app_id"].as_str().map(str::to_owned),
            title: value["title"].as_str().map(str::to_owned),
        })
    }
}

pub fn windows() -> Result<Vec<Window>, String> {
    let list = query("windows")?;
    Ok(list
        .as_array()
        .map(|items| items.iter().filter_map(Window::from_value).collect())
        .unwrap_or_default())
}

pub fn focused_window() -> Result<Option<Window>, String> {
    Ok(Window::from_value(&query("focused-window")?))
}

pub fn focus(id: u64) {
    let _ = Command::new("niri")
        .args(["msg", "action", "focus-window", "--id", &id.to_string()])
        .output();
}

pub fn event_stream() -> std::io::Result<Child> {
    Command::new("niri")
        .args(["msg", "-j", "event-stream"])
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
}

fn query(what: &str) -> Result<Value, String> {
    let output = Command::new("niri")
        .args(["msg", "-j", what])
        .output()
        .map_err(|error| format!("niri msg {what}: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "niri msg {what}: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|error| format!("niri msg {what}: {error}"))
}
