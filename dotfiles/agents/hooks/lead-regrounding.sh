#!/usr/bin/env bash
# Claude Code PostToolUse(Agent) hook for the main session only: on the
# session's first worker spawn it tells the lead to create the recurring
# 20-minute DAG regrounding CronCreate. Subagent payloads (agent_id or
# agent_type present) get nothing. Fires once per session_id, recorded under
# ~/.local/state/agents/regrounding/.
#
# Kill-switch: `north config agents off lead-regrounding` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

payload="$(head -c 1048577)"
[ "${#payload}" -le 1048576 ] || exit 0
case "$payload" in
  *'"tool_name":"Agent"'*|*'"tool_name": "Agent"'*) ;;
  *) exit 0 ;;
esac
case "$payload" in
  *'"agent_id"'*|*'"agent_type"'*) exit 0 ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import json, os, re, sys

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("tool_name") != "Agent":
    sys.exit(0)
if data.get("agent_id") or data.get("agent_type"):
    sys.exit(0)
session = data.get("session_id")
if not (isinstance(session, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", session)):
    sys.exit(0)

state = os.path.join(os.path.expanduser("~"), ".local/state/agents/regrounding")
marker = os.path.join(state, session)
try:
    os.makedirs(state, exist_ok=True)
    fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    os.close(fd)
except FileExistsError:
    sys.exit(0)
except OSError:
    sys.exit(0)

prompt = (
    "Lead regrounding tick. 1. Reread the goal and the status file. "
    "2. Rebuild the DAG from the goal's GitHub issues, main CI, cloud runs and queued landings. "
    "3. Name the critical path's longest wait and attack it: batch ready lanes into one landing, "
    "run unknown-cause bugs as 2-3 parallel hypotheses, have art or judged work render 2-4 variants per pass and judge once, "
    "and send code-only work to cloud workers. "
    "4. Staff every unblocked node up to the spawn gate and recycle every worker running 30 minutes from a handoff. "
    "5. Close issues whose boxes passed. "
    "6. Write one status line."
)
text = (
    "You spawned your first worker this session. As a lead with a goal, create the "
    "recurring regrounding job now if you have not: CronCreate with cron \"*/20 * * * *\", "
    "recurring true, and this exact prompt: " + json.dumps(prompt)
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
