#!/usr/bin/env bash
# Claude PreToolUse(Agent) spawn gate: refuses a new local worker while CPU
# pressure (some avg60) is at or above the limit in lib/spawn_capacity.py.
# Remote workers, other tools, a missing interpreter and malformed input allow.
#
# Kill-switch: `north config agents off spawn-capacity-guard` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
set -uo pipefail

payload="$(head -c 1048576)"
case "$payload" in
  *'"tool_name":"Agent"'*|*'"tool_name": "Agent"'*) ;;
  *) exit 0 ;;
esac

# Most spawns happen under the limit; decide those here without starting Python.
# The limit is read from the decider so it stays in one constant.
decider="$(dirname "$0")/lib/spawn_capacity.py"
hundredths() {
  local whole="${1%%.*}" frac="${1#*.}"
  [ "$frac" = "$1" ] && frac=0
  frac="${frac}00"
  printf '%d' "$((10#${whole:-0} * 100 + 10#${frac:0:2}))"
}
limit="" avg60=""
while IFS= read -r line; do
  case "$line" in PRESSURE_LIMIT\ =\ *) limit="${line#PRESSURE_LIMIT = }"; break ;; esac
done 2>/dev/null <"$decider"
[ -n "$limit" ] || exit 0
read -r kind rest 2>/dev/null <"${SPAWN_CAPACITY_PRESSURE:-/proc/pressure/cpu}" || exit 0
[ "$kind" = some ] || exit 0
for field in $rest; do
  case "$field" in avg60=*) avg60="${field#avg60=}" ;; esac
done
case "$avg60" in ''|*[!0-9.]*) exit 0 ;; esac
[ "$(hundredths "$avg60")" -ge "$(hundredths "$limit")" ] || exit 0

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

python_bin="${NORTH_AGENT_PYTHON:-python3}"
command -v -- "$python_bin" >/dev/null 2>&1 && [ -r "$decider" ] || exit 0
printf '%s' "$payload" | "$python_bin" "$decider" 2>/dev/null
exit 0
