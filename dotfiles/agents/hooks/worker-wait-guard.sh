#!/usr/bin/env bash
# PreToolUse(Bash) guard for Claude Code workers (agent_type worker*): refuses a
# foreground command that can block past 60 seconds (waits, sleeps, safe-push,
# leased runs, suites, farm runs, timeouts over 60 s). Messages reach a worker
# only between tool calls, so long work runs with run_in_background and the
# lead's messages arrive at once.
#
# Kill-switch: `north config agents off worker-wait-guard` or env
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
import json, re, sys

LIMIT_S = 60

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("tool_name") != "Bash":
    sys.exit(0)
agent_type = data.get("agent_type")
if not (isinstance(agent_type, str) and agent_type.startswith("worker")):
    sys.exit(0)
tool_input = data.get("tool_input") or {}
if not isinstance(tool_input, dict) or tool_input.get("run_in_background") is True:
    sys.exit(0)
command = tool_input.get("command")
if not isinstance(command, str):
    sys.exit(0)

reason = None
timeout = tool_input.get("timeout")
if isinstance(timeout, (int, float)) and timeout > LIMIT_S * 1000:
    reason = f"a timeout of {int(timeout // 1000)} s"
else:
    patterns = [
        (r"\buntil\b[\s\S]*\bsleep\b", "an until/sleep wait loop"),
        (r"\bwhile\b[\s\S]*\bsleep\b", "a while/sleep wait loop"),
        (r"\bsafe-push\b", "safe-push"),
        (r"\bgh\s+run\s+watch\b|\bgh\s+pr\s+checks\b[^\n]*--watch", "a CI watch"),
        (r"machine-capacity\.mjs\s+(run|session)\b", "a leased run"),
        (r"\bbun\s+(run\s+)?test\b(?!\s+\S+\.test\.ts)", "a test suite"),
        (r"\bbun\s+wisp\s+farm\b", "a farm run"),
    ]
    for pattern, label in patterns:
        if re.search(pattern, command):
            reason = label
            break
    if reason is None:
        for m in re.finditer(r"\b(?:sleep|timeout)\s+(\d+)", command):
            if int(m.group(1)) > LIMIT_S:
                reason = f"`{m.group(0)}`"
                break
if reason is None:
    sys.exit(0)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Workers never block in the foreground on {reason}: the lead's messages "
            "reach you only between tool calls and must arrive at once. Rerun it with "
            "run_in_background: true and wait for its completion notification or a "
            "Monitor event, checking messages in between."
        ),
    }
}))
PYEOF

printf '%s' "$payload" | "${NORTH_AGENT_PYTHON:-python3}" -c "$PY"
exit 0
