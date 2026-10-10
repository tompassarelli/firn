#!/usr/bin/env bash
# PostToolUse hook for Claude Code workers (agent_type worker*). When the
# worker's context reaches 350k tokens (before 500k auto-compaction) it tells
# the worker to land what passes and hand off the rest; it repeats at most once
# per further 50k. After 45 minutes of
# wall-clock time since the transcript's first entry it tells the worker to
# report or hand off; it repeats at most once per further 10 minutes. The main
# session and other agent types get nothing. Runs after every tool call, so it
# reads only the transcript head and tail.
#
# Kill-switch: `north config agents off worker-handoff` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

capture_hook_stdin() {
  local chunk status keep
  local LC_ALL=C
  payload=""
  payload_oversized=0
  while :; do
    chunk=""
    IFS= read -r -N 65536 chunk
    status=$?
    if [ -n "$chunk" ]; then
      keep=$((1048576 - ${#payload}))
      [ "$keep" -le 0 ] || payload+="${chunk:0:$keep}"
      [ "${#chunk}" -le "$keep" ] || payload_oversized=1
    fi
    [ "$status" -eq 0 ] || break
  done
}
capture_hook_stdin

case "$payload" in
  *'"agent_type"'*'"worker'*) ;;
  *) exit 0 ;;
esac
[ "$payload_oversized" -eq 0 ] || exit 0

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type hook_decide >/dev/null 2>&1 || exit 0
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import json, os, re, sys, time
from datetime import datetime

THRESHOLD = 350_000
STEP = 50_000
LEASH_MIN = 45
LEASH_STEP_MIN = 10

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(65)
if not isinstance(data, dict):
    sys.exit(0)
agent_type = data.get("agent_type")
agent_id = data.get("agent_id")
transcript = data.get("agent_transcript_path")
if not (isinstance(agent_type, str) and agent_type.startswith("worker")):
    sys.exit(0)
if not (isinstance(agent_id, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", agent_id)):
    sys.exit(0)
if not isinstance(transcript, str):
    sys.exit(0)

def context_tokens(path):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            for window in (256 << 10, 4 << 20):
                start = max(0, size - window)
                f.seek(start)
                lines = f.read().splitlines()
                if start:
                    lines = lines[1:]
                for raw in reversed(lines):
                    if b'"usage"' not in raw:
                        continue
                    try:
                        entry = json.loads(raw)
                    except ValueError:
                        continue
                    if entry.get("type") != "assistant":
                        continue
                    usage = (entry.get("message") or {}).get("usage") or {}
                    total = sum(int(usage.get(k) or 0) for k in (
                        "input_tokens",
                        "cache_read_input_tokens",
                        "cache_creation_input_tokens",
                    ))
                    if total:
                        return total
                if not start:
                    break
    except (OSError, ValueError, TypeError):
        pass
    return 0

def started_at(path):
    try:
        with open(path, "rb") as f:
            for _ in range(8):
                raw = f.readline(1 << 20)
                if not raw:
                    break
                try:
                    stamp = json.loads(raw).get("timestamp")
                except (ValueError, AttributeError):
                    continue
                if isinstance(stamp, str):
                    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except (OSError, ValueError):
        pass
    return None

handoffs = os.path.join(os.path.expanduser("~"), ".local/state/agents/handoffs")

def due(marker, value, step):
    try:
        with open(marker) as f:
            last = int(f.read().strip() or 0)
    except (OSError, ValueError):
        last = 0
    if last and value < last + step:
        return False
    try:
        os.makedirs(handoffs, exist_ok=True)
        with open(marker, "w") as f:
            f.write(f"{value}\n")
    except OSError:
        return False
    return True

messages = []

tokens = context_tokens(transcript)
note = os.path.join(handoffs, f"{agent_id}.md")
if tokens >= THRESHOLD and due(os.path.join(handoffs, f".{agent_id}.reminded"), tokens, STEP):
    messages.append(
        f"Your context is {tokens // 1000}k tokens, past the {THRESHOLD // 1000}k handoff point. "
        "Land anything that passes now; if work remains, finish the step you are on, then write a handoff note to "
        f"{note} with: the brief's goal and Done when list with each box's status; "
        "the worktree, branch and commits; running background jobs with their "
        "output paths; the next step; evidence paths. Then end your turn with "
        f"exactly `HANDOFF {note}` and nothing else."
    )

start = started_at(transcript)
minutes = int((time.time() - start) // 60) if start is not None else 0
if minutes >= LEASH_MIN and due(os.path.join(handoffs, f".{agent_id}.leash"), minutes, LEASH_STEP_MIN):
    messages.append(
        f"You have run {LEASH_MIN} minutes. Land anything that passes now, then either "
        "report (Done:/Not done:/Blocked:) or write a handoff to "
        "~/.local/state/agents/handoffs/<lane>.md, commit your WIP and report "
        "Not done: with its path."
    )

if not messages:
    sys.exit(0)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": " ".join(messages),
    }
}))
PYEOF

hook_decide "${NORTH_AGENT_PYTHON:-python3}" -c "$PY"
exit 0
