#!/usr/bin/env bash
# Claude PreToolUse(Agent) spawn gate: refuses a new local worker once capacity
# leases hold the machine's CPU limit or the protected desktop slice is under
# pressure (rules in lib/spawn_capacity.py). Remote workers, other tools, a
# missing interpreter or helper and malformed input allow.
#
# Kill-switch: `north config agents off spawn-capacity-guard` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

payload="$(head -c 1048576)"
case "$payload" in
  *'"tool_name":"Agent"'*|*'"tool_name": "Agent"'*) ;;
  *) exit 0 ;;
esac

decider="$(dirname "$0")/lib/spawn_capacity.py"
python_bin="${NORTH_AGENT_PYTHON:-python3}"
command -v -- "$python_bin" >/dev/null 2>&1 && [ -r "$decider" ] || exit 0
decision="$(printf '%s' "$payload" | "$python_bin" "$decider" 2>/dev/null)"
[ -n "$decision" ] || exit 0

# Only a refusal pays for the activation lookup behind the kill-switch.
authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
printf '%s\n' "$decision"
exit 0
