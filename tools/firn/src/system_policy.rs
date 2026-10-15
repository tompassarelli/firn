use serde::de::{Deserialize, Deserializer, MapAccess, Visitor};
use serde_json::value::RawValue;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;

const LIMIT: u64 = 1_048_576;
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
const REASON: &str = concat!(
    "BLOCKED: raw nixos-rebuild/darwin-rebuild/nh bypasses the sanctioned ",
    "snapshot workflow. Use `firn rebuild` after the relevant checks pass ",
    "and owned changes are committed."
);

struct Object(Vec<(String, Box<RawValue>)>);

impl<'de> Deserialize<'de> for Object {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ObjectVisitor;
        impl<'de> Visitor<'de> for ObjectVisitor {
            type Value = Object;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("an object")
            }
            fn visit_map<M: MapAccess<'de>>(self, mut map: M) -> Result<Object, M::Error> {
                let mut fields = Vec::new();
                while let Some(field) = map.next_entry()? {
                    fields.push(field);
                }
                Ok(Object(fields))
            }
        }
        deserializer.deserialize_map(ObjectVisitor)
    }
}

impl Object {
    fn field<T: serde::de::DeserializeOwned>(&self, name: &str) -> Option<T> {
        self.0
            .iter()
            .find(|(key, _)| key == name)
            .and_then(|(_, raw)| serde_json::from_str(raw.get()).ok())
    }

    fn string(&self, name: &str) -> Option<String> {
        self.field::<String>(name)
    }
}

fn bounded(mut reader: impl Read) -> Option<String> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take(LIMIT + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > LIMIT as usize {
        let _ = io::copy(&mut reader, &mut io::sink());
        return None;
    }
    (bytes.len() <= LIMIT as usize).then(|| String::from_utf8_lossy(&bytes).into_owned())
}

fn object(text: &str) -> Option<Object> {
    let root = serde_json::from_str(text).ok()?;
    let bytes = text.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] != b'"' {
            at += 1;
            continue;
        }
        let start = at;
        at += 1;
        while at < bytes.len() && bytes[at] != b'"' {
            if bytes[at] == b'\\' {
                at += 1;
            }
            at += 1;
        }
        serde_json::from_str::<String>(text.get(start..=at)?).ok()?;
        at += 1;
    }
    Some(root)
}

fn active(text: &str) -> bool {
    let Some(root) = object(text) else {
        return false;
    };
    if root.string("schema").as_deref() != Some("north.agent-activation/v1")
        || root.string("catalogDigest").is_none()
        || root.string("generationId").is_none()
    {
        return false;
    }
    let Some(units) = root.field::<Vec<Box<RawValue>>>("units") else {
        return false;
    };
    let mut matched = false;
    let mut enabled = false;
    for raw in units {
        let Ok(unit) = serde_json::from_str::<Object>(raw.get()) else {
            return false;
        };
        if unit.string("kind").as_deref() == Some("hook")
            && unit.string("id").as_deref() == Some("firn-system-policy")
        {
            if matched {
                return false;
            }
            matched = true;
            enabled = unit.string("permission").as_deref() == Some("on")
                && unit.field::<bool>("active") == Some(true);
        }
    }
    matched && enabled
}

fn guards_off() -> bool {
    if let Ok(value) = env::var("AGENT_NO_AUTHORING_HOOKS") {
        if !value.is_empty() {
            return value != "0" && value != "false";
        }
    }
    let root = env::var("NORTH_AGENT_STATE_ROOT")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| {
            env::var("HOME")
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| format!("{s}/.local/state/north/agents"))
        });
    root.and_then(|root| fs::File::open(format!("{root}/current/activation.json")).ok())
        .and_then(bounded)
        .is_none_or(|text| !active(&text))
}

fn intro_unseen(session: &str) -> bool {
    let directory = env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/tmp".into());
    let session: String = session
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"_.-".contains(&b) {
                b as char
            } else {
                '_'
            }
        })
        .collect();
    let marker = PathBuf::from(format!("{directory}/firn-system-policy.{session}"));
    if !matches!(fs::symlink_metadata(&marker), Err(error) if error.raw_os_error() == Some(2)) {
        return false;
    }
    let temporary = marker.with_file_name(format!(
        "{}.firn-{}",
        marker.file_name().unwrap().to_string_lossy(),
        std::process::id()
    ));
    if OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary)
        .is_ok()
    {
        let _ = fs::rename(&temporary, &marker);
        let _ = fs::remove_file(&temporary);
    }
    true
}

fn whitespace(b: u8) -> bool {
    b" \t\n".contains(&b)
}
fn separator(b: u8) -> bool {
    whitespace(b) || b";&|(`)".contains(&b)
}
fn anchor(text: &[u8], at: usize) -> bool {
    at == 0 || b"\n;&|(`".contains(&text[at - 1])
}
fn skip(text: &[u8], mut at: usize) -> usize {
    while at < text.len() && whitespace(text[at]) {
        at += 1;
    }
    at
}
fn token_end(text: &[u8], mut at: usize) -> usize {
    while at < text.len() && !separator(text[at]) {
        at += 1;
    }
    at
}
fn next_word(text: &[u8], at: usize) -> usize {
    skip(text, token_end(text, skip(text, at)))
}
fn word(text: &[u8], at: usize, word: &[u8]) -> bool {
    text.get(at..at + word.len()) == Some(word)
        && (at + word.len() == text.len()
            || text.get(at + word.len()).is_some_and(|b| separator(*b)))
}
fn has_word(text: &[u8], at: usize, wanted: &[u8]) -> bool {
    let mut cursor = next_word(text, at);
    while cursor < text.len() && !anchor(text, cursor) {
        if word(text, cursor, wanted) {
            return true;
        }
        if token_end(text, cursor) == cursor {
            return false;
        }
        cursor = next_word(text, cursor);
    }
    false
}
fn refused(command: &str) -> bool {
    let text = command.as_bytes();
    (0..text.len()).any(|at| {
        if !anchor(text, at) {
            return false;
        }
        let mut start = skip(text, at);
        if word(text, start, b"sudo") || word(text, start, b"doas") {
            start = next_word(text, start);
        }
        let next = next_word(text, start);
        (word(text, start, b"nixos-rebuild")
            && [b"switch".as_slice(), b"boot", b"test"]
                .iter()
                .any(|w| has_word(text, start, w)))
            || (word(text, start, b"darwin-rebuild")
                && [b"switch".as_slice(), b"boot"]
                    .iter()
                    .any(|w| has_word(text, start, w)))
            || (word(text, start, b"nh")
                && (word(text, next, b"switch")
                    || word(text, next, b"boot")
                    || (word(text, next, b"os")
                        && (word(text, next_word(text, next), b"switch")
                            || word(text, next_word(text, next), b"boot")))))
    })
}

fn decision(text: &str) -> Option<(&'static str, &'static str)> {
    let root = object(text)?;
    let tool = root.string("tool_name").unwrap_or_default();
    let input = root.field::<Object>("tool_input")?;
    let path = input
        .string("file_path")
        .or_else(|| input.string("filePath"));
    let path = path.map(|path| {
        fs::canonicalize(&path)
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or(path)
    });
    let unseen = path.as_ref().is_some_and(|path| {
        ["Edit", "Write", "MultiEdit"].contains(&tool.as_str())
            && path.contains("/code/nixos-config/")
            && intro_unseen(
                &root
                    .string("session_id")
                    .unwrap_or_else(|| "nosession".into()),
            )
    });
    if tool == "Bash"
        && input
            .string("command")
            .is_some_and(|command| refused(&command))
    {
        Some(("permissionDecisionReason", REASON))
    } else if unseen {
        Some(("additionalContext", DIGEST))
    } else {
        None
    }
}

pub fn run() {
    let Some(text) = bounded(io::stdin().lock()) else {
        return;
    };
    if guards_off() {
        return;
    }
    if let Some((key, message)) = decision(text.strip_prefix('\u{feff}').unwrap_or(&text)) {
        let deny = if key == "permissionDecisionReason" {
            "\"permissionDecision\":\"deny\","
        } else {
            ""
        };
        let output = format!(
            "{{\"hookSpecificOutput\":{{\"hookEventName\":\"PreToolUse\",{deny}\"{key}\":{}}}}}\n",
            serde_json::to_string(message).unwrap()
        );
        let _ = io::stdout().lock().write_all(output.as_bytes());
    }
}
