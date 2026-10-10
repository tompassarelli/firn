#!/usr/bin/env bash
# Claude SubagentStop hook: refuses to let a subagent finish while background
# tasks it started (Bash run_in_background, commands moved to the background,
# Monitor) are still running, so a finished worker clears from the terminal
# and never re-notifies later. A task has ended when the transcript holds a
# TaskStop or a task notification for it; a shell task has also ended when no
# process holds its output file open; a Monitor has also ended once its
# timeout has passed. stop_hook_active, an unreadable transcript and malformed
# input allow.
#
# Kill-switch: `north config agents off subagent-teardown` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

payload="$(head -c 1048576)"
case "$payload" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
  *'transcript_path"'*) ;;
  *) exit 0 ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import calendar, json, os, re, sys, time

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(65)
if not isinstance(data, dict) or data.get("stop_hook_active") is True:
    sys.exit(0)
path = data.get("agent_transcript_path")
if not isinstance(path, str):
    path = data.get("transcript_path")
    if not (isinstance(path, str) and "/subagents/" in path):
        sys.exit(0)

uses = {}      # tool_use_id -> (kind, description, start epoch, timeout ms)
tasks = {}     # task id -> (kind, description, output path, start, timeout)
ended = set()
ID_RE = re.compile(r"(?:with ID: |\(task )([A-Za-z0-9_-]+)")
OUT_RE = re.compile(r"Output is being written to: (\S+?\.output)")
NOTE_RE = re.compile(r"<task-id>([A-Za-z0-9_-]+)</task-id>")

def epoch(stamp):
    try:
        return calendar.timegm(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return time.time()

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""

try:
    with open(path, "rb") as f:
        for raw in f:
            if b"task-id>" in raw:
                ended.update(NOTE_RE.findall(raw.decode("utf-8", "replace")))
            if b'"tool_use' not in raw and b"toolUseResult" not in raw:
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            content = (entry.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    name, inp = block.get("name"), block.get("input") or {}
                    if name == "TaskStop":
                        tid = inp.get("task_id") or inp.get("shell_id")
                        if isinstance(tid, str):
                            ended.add(tid)
                    elif name in ("Bash", "Monitor"):
                        uses[block.get("id")] = (
                            name,
                            str(inp.get("description") or "")[:80],
                            epoch(str(entry.get("timestamp") or "")),
                            inp.get("timeout_ms"),
                        )
                elif block.get("type") == "tool_result" and block.get("tool_use_id") in uses:
                    kind, desc, start, timeout = uses[block["tool_use_id"]]
                    result = entry.get("toolUseResult")
                    result = result if isinstance(result, dict) else {}
                    body = text_of(block.get("content"))
                    tid = result.get("backgroundTaskId") or (
                        result.get("taskId") if kind == "Monitor" else None)
                    if not tid and ("in background with ID" in body or "Monitor started" in body):
                        m = ID_RE.search(body)
                        tid = m.group(1) if m else None
                    if isinstance(tid, str):
                        m = OUT_RE.search(body)
                        tasks[tid] = (kind, desc, m.group(1) if m else None, start, timeout)
except OSError:
    sys.exit(0)

pending = {t: v for t, v in tasks.items() if t not in ended}
if not pending:
    sys.exit(0)

now = time.time()
for tid, (kind, _, _, start, timeout) in list(pending.items()):
    if kind == "Monitor":
        limit = timeout if isinstance(timeout, (int, float)) else 300000
        if start + min(limit, 3600000) / 1000 < now:
            del pending[tid]

outputs = {v[2] for v in pending.values() if v[0] == "Bash" and v[2]}
held = set()
if outputs:
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            fds = os.listdir(f"/proc/{pid}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target in outputs:
                held.add(target)
for tid, (kind, _, out, _, _) in list(pending.items()):
    if kind == "Bash" and out and out not in held:
        del pending[tid]
if not pending:
    sys.exit(0)

names = ", ".join(f"{t} ({v[1] or v[0]})" for t, v in pending.items())
print(json.dumps({
    "decision": "block",
    "reason": f"You still have background tasks running: {names}. "
              "Stop each with TaskStop, then finish your report.",
}))
PYEOF

python_bin="${NORTH_AGENT_PYTHON:-python3}"
hook_decide "$python_bin" -c "$PY"
exit 0
