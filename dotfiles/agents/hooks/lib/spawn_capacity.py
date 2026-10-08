#!/usr/bin/env python3
"""Spawn gate: refuse a new local worker while the machine is CPU-starved.

Shared by the Claude PreToolUse(Agent) hook (spawn-capacity-guard.sh) and the
Codex behavior guard's PreToolUse(spawn_agent). Reads only /proc/pressure/cpu
"some avg60"; an unreadable or malformed file allows. An urgent fix passes with
`CASE=URGENT FACT="..."` at the start of the brief, logged beside the Codex
behavior overrides.
"""

import json
import os
import re
import sys
import time
from pathlib import Path

PRESSURE_LIMIT = 40.0
LOCAL_CLAUDE_TYPES = {"worker", "worker-high", "worker-haiku", "general-purpose", "Explore", "fork"}
ACTIVE_SECONDS = 300
URGENT = re.compile(r"^\s*CASE=URGENT\s+FACT=(\"([^\"]*)\"|'([^']*)')", re.IGNORECASE)


def pressure_path():
    return os.environ.get("SPAWN_CAPACITY_PRESSURE", "/proc/pressure/cpu")


def cpu_pressure():
    try:
        with open(pressure_path()) as f:
            for line in f:
                if line.startswith("some "):
                    match = re.search(r"\bavg60=([0-9.]+)", line)
                    return float(match.group(1)) if match else None
    except (OSError, ValueError):
        return None
    return None


def local_workers():
    """Claude subagent transcripts and Codex rollouts written in the last five minutes."""
    home = Path(os.environ.get("SPAWN_CAPACITY_HOME", Path.home()))
    cutoff = time.time() - ACTIVE_SECONDS
    count = 0
    patterns = [
        (home / ".claude" / "projects", "*/*/subagents/*.jsonl"),
        (home / ".codex" / "sessions", time.strftime("%Y/%m/%d") + "/*.jsonl"),
    ]
    for root, pattern in patterns:
        try:
            for path in root.glob(pattern):
                try:
                    if path.stat().st_mtime >= cutoff:
                        count += 1
                except OSError:
                    pass
        except OSError:
            pass
    return count


def state_root():
    return Path(
        os.environ.get(
            "CODEX_BEHAVIOR_STATE",
            Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "codex-behavior",
        )
    )


def log_override(event, fact):
    try:
        root = state_root()
        root.mkdir(parents=True, exist_ok=True)
        with open(root / "verify-overrides.jsonl", "a") as log:
            log.write(json.dumps({
                "at": time.time(), "session": event.get("session_id"), "agent": event.get("agent_id"),
                "gate": "spawn-capacity", "case": "URGENT", "cwd": event.get("cwd"), "fact": fact[:300],
            }) + "\n")
    except OSError:
        pass


def is_local(event):
    tool = str(event.get("tool_name") or "")
    tool_input = event.get("tool_input") or {}
    if tool.endswith("spawn_agent"):
        return True
    if tool != "Agent" or not isinstance(tool_input, dict):
        return False
    if tool_input.get("isolation") == "remote":
        return False
    return (tool_input.get("subagent_type") or "general-purpose") in LOCAL_CLAUDE_TYPES


def brief_texts(tool_input):
    """Every string in the spawn input; Codex may send it as serialized JSON."""
    if isinstance(tool_input, str):
        try:
            parsed = json.loads(tool_input)
        except ValueError:
            return [tool_input]
        return [tool_input] if isinstance(parsed, str) else brief_texts(parsed)
    if isinstance(tool_input, dict):
        return [t for value in tool_input.values() for t in brief_texts(value)]
    if isinstance(tool_input, list):
        return [t for value in tool_input for t in brief_texts(value)]
    return []


def check(event):
    """The refusal text for this spawn, or None to allow it."""
    if not is_local(event):
        return None
    pressure = cpu_pressure()
    if pressure is None or pressure < PRESSURE_LIMIT:
        return None
    urgent = next((m for m in map(URGENT.match, brief_texts(event.get("tool_input") or {})) if m), None)
    if urgent:
        fact = urgent.group(2) if urgent.group(2) is not None else urgent.group(3)
        if len(fact.strip()) >= 15:
            log_override(event, fact.strip())
            return None
    return (
        f"The machine is at {pressure:g}% CPU pressure (limit {PRESSURE_LIMIT:g}%) with "
        f"{local_workers()} local workers running. Queue this worker until pressure falls, "
        "send heavy checks to the farm, or use a cloud worker for code-only work "
        "(cloud-workers skill). Workers already running are unaffected. For an urgent fix, "
        "start the brief with CASE=URGENT FACT=\"<why it can't wait>\"."
    )


def main():
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    reason = check(event) if isinstance(event, dict) else None
    if reason:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
