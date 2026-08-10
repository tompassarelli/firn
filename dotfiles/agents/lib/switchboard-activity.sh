# shellcheck shell=bash

# Read one unit from the switchboard's derived activity projection. A machine
# without the projection predates this integration and keeps its existing
# behavior; once the projection exists, a missing or inactive row is off.
agents_switchboard_active() {
  local wanted_kind="$1" wanted_name="$2"
  local activity_file="${AGENTS_ACTIVITY_FILE:-$HOME/.config/agents/activity.conf}"
  local kind name state rest

  [ -r "$activity_file" ] || return 0
  while read -r kind name state rest; do
    if [ "$kind" = "$wanted_kind" ] && [ "$name" = "$wanted_name" ]; then
      [ "$state" = on ]
      return
    fi
  done < "$activity_file"
  return 1
}
