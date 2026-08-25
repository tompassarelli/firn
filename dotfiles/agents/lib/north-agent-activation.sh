# shellcheck shell=bash

north_agent_activation_path() {
  local state_root="${NORTH_AGENT_STATE_ROOT:-$HOME/.local/state/north/agents}"
  printf '%s\n' "$state_root/current/activation.json"
}

# North resolves permission, module closure, support claims, and every kill switch
# before publishing one immutable activation generation. Provider adapters read
# only that resolved decision; a missing or malformed generation is inactive.
north_agent_unit_active() {
  local wanted_kind="$1" wanted_id="$2" activation python_bin
  activation="$(north_agent_activation_path)" || return 1
  python_bin="${NORTH_AGENT_PYTHON:-python3}"
  [ -r "$activation" ] && [ -x "$python_bin" ] || return 1

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
