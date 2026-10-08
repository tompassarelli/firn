#!/usr/bin/env bash
# PostToolUse hook for Claude Code workers (agent_type worker*). When the
# worker's context reaches 400k tokens it tells the worker to write a handoff
# note and stop; it repeats at most once per further 50k. The main session and
# other agent types get nothing. Runs after every tool call, so it reads only
# the transcript tail.
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
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import json, os, re, sys

THRESHOLD = 400_000
STEP = 50_000

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
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

tokens = context_tokens(transcript)
if tokens < THRESHOLD:
    sys.exit(0)

handoffs = os.path.join(os.path.expanduser("~"), ".local/state/agents/handoffs")
note = os.path.join(handoffs, f"{agent_id}.md")
marker = os.path.join(handoffs, f".{agent_id}.reminded")
try:
    with open(marker) as f:
        last = int(f.read().strip() or 0)
except (OSError, ValueError):
    last = 0
if last and tokens < last + STEP:
    sys.exit(0)
try:
    os.makedirs(handoffs, exist_ok=True)
    with open(marker, "w") as f:
        f.write(f"{tokens}\n")
except OSError:
    sys.exit(0)

text = (
    f"Your context is {tokens // 1000}k tokens, past the 400k handoff point. "
    "Finish the step you are on, then write a handoff note to "
    f"{note} with: the brief's goal and Done when list with each box's status; "
    "the worktree, branch and commits; running background jobs with their "
    "output paths; the next step; evidence paths. Then end your turn with "
    f"exactly `HANDOFF {note}` and nothing else."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": text,
    }
}))
PYEOF

printf '%s' "$payload" | "${NORTH_AGENT_PYTHON:-python3}" -c "$PY"
exit 0
