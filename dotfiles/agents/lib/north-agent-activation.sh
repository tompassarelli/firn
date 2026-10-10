# shellcheck shell=bash

# North resolves permission, module closure, support claims and every kill switch
# into one immutable generation. Its activation.active lists one `kind id` line
# per active unit; a generation from before that list falls back to the JSON.
north_agent_unit_active() {
  local wanted="$1 $2" line
  local list="${NORTH_AGENT_STATE_ROOT:-$HOME/.local/state/north/agents}/current/activation.active"
  [ -z "${NORTH_AGENT_ACTIVATION:-}" ] || list="${NORTH_AGENT_ACTIVATION%.json}.active"
  list="${NORTH_AGENT_ACTIVE:-$list}"
  if [ -r "$list" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ "$line" != "$wanted" ] || return 0
    done <"$list"
    return 1
  fi
  north_agent_unit_active_json "$1" "$2"
}

north_agent_activation_path() {
  if [ -n "${NORTH_AGENT_ACTIVATION:-}" ]; then
    printf '%s\n' "$NORTH_AGENT_ACTIVATION"
  elif [ -n "${NORTH_AGENT_ACTIVE:-}" ]; then
    printf '%s\n' "${NORTH_AGENT_ACTIVE%.active}.json"
  else
    printf '%s\n' "${NORTH_AGENT_STATE_ROOT:-$HOME/.local/state/north/agents}/current/activation.json"
  fi
}

north_agent_unit_active_json() {
  local wanted_kind="$1" wanted_id="$2" activation python_bin
  activation="$(north_agent_activation_path)" || return 1
  python_bin="${NORTH_AGENT_PYTHON:-python3}"
  if [[ "$python_bin" != */* ]]; then
    python_bin="$(command -v -- "$python_bin")" || python_bin=''
  fi
  [ -r "$activation" ] || return 1
  if [ ! -x "$python_bin" ]; then
    ! type hook_error >/dev/null 2>&1 || hook_error missing-interpreter
    return 1
  fi

  "$python_bin" - "$activation" "$wanted_kind" "$wanted_id" 2>/dev/null <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)

digest = re.compile(r"^sha256:[0-9a-f]{64}$")
permission = re.compile(r"^(on|off)$")
if (
    data.get("schema") != "north.agent-activation/v1"
    or not digest.fullmatch(data.get("catalogDigest", ""))
    or not digest.fullmatch(data.get("generationId", ""))
):
    raise SystemExit(1)
units = data.get("units")
if not isinstance(units, list):
    raise SystemExit(1)
matches = [
    unit for unit in units
    if isinstance(unit, dict)
    and unit.get("kind") == sys.argv[2]
    and unit.get("id") == sys.argv[3]
]
if (
    len(matches) != 1
    or not isinstance(matches[0].get("permission"), str)
    or not permission.fullmatch(matches[0]["permission"])
    or matches[0]["permission"] != "on"
    or matches[0].get("active") is not True
):
    raise SystemExit(1)
PY
}
