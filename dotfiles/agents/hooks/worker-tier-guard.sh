#!/usr/bin/env bash
# Claude PreToolUse(Agent) tier gate for lead sessions: a `Category: mechanical`
# or `Category: docs-policy` brief goes to worker-haiku, and worker-high or
# worker-xhigh take only escalations. A `Follows:` line marks an escalation and
# allows any worker tier. Non-worker agent types always allow.
#
# Kill-switch: `north config agents off worker-tier-guard` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

payload="$(head -c 1048576)"
case "$payload" in
  *'"subagent_type"'*'"worker'*) ;;
  *) exit 0 ;;
esac

read -r -d '' PY <<'PYEOF' || true
import json, re, sys

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("tool_name") != "Agent":
    sys.exit(0)
ti = data.get("tool_input") or {}
if not isinstance(ti, dict):
    sys.exit(0)
kind = ti.get("subagent_type")
prompt = ti.get("prompt")
if not isinstance(kind, str) or not kind.startswith("worker") or not isinstance(prompt, str):
    sys.exit(0)
if re.search(r"(?mi)^\W*Follows:\s*\S", prompt):
    sys.exit(0)
reason = None
m = re.search(r"(?mi)\bCategory:\W*(mechanical|docs-policy)\b", prompt)
if m and kind != "worker-haiku":
    reason = (
        f"Category: {m.group(1).lower()} goes to worker-haiku, not {kind}: mechanical and "
        "docs-policy work goes to Haiku (ledger 28/31 mechanical). Escalate to worker only "
        "after a Haiku failure, and say so with a `Follows:` line naming the failed run."
    )
elif kind in ("worker-high", "worker-xhigh"):
    reason = (
        f"{kind} is escalation-only: assign worker first, and escalate only after its "
        "reasoning failure, saying so with a `Follows:` line naming the failed run."
    )
if reason is None:
    sys.exit(0)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": reason,
}}))
PYEOF

decision="$(printf '%s' "$payload" | "${NORTH_AGENT_PYTHON:-python3}" -c "$PY" 2>/dev/null)"
[ -n "$decision" ] || exit 0

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
printf '%s\n' "$decision"
exit 0
