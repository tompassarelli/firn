#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
agents="$repo/dotfiles/bin/agents"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agents-thin-client.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

state="$scratch/state"
bin="$scratch/bin"
log="$scratch/north.calls"
mkdir -p "$state/current" "$bin"

cat >"$state/current/activation.json" <<'JSON'
{
  "schema": "north.agent-activation/v1",
  "catalogSchema": "north.agent-catalog/v1",
  "catalogDigest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "generationId": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "baselines": [],
  "permissions": {"coordination":"on","build-vs-reuse":"off","north-session-lifecycle":"on"},
  "rootOrder": ["coordination","build-vs-reuse","north-session-lifecycle"],
  "units": [
    {
      "id": "coordination",
      "kind": "set",
      "title": "Coordination",
      "triggerDescription": "Durable coordination workflows.",
      "permission": "on",
      "active": true,
      "owner": {"repo": "north", "path": "agent-catalog/catalog.json"},
      "members": ["messages", "threads", "assignments"],
      "supports": [],
      "distributions": [],
      "activationPaths": []
    },
    {
      "id": "build-vs-reuse",
      "kind": "skill",
      "title": "Build versus reuse",
      "triggerDescription": "Choose whether to build or reuse an implementation.",
      "permission": "off",
      "active": false,
      "owner": {"repo": "north", "path": "profiles/tom/skills/build-vs-reuse/SKILL.md"},
      "members": [],
      "supports": [],
      "distributions": [{"type":"skill","targets":["shared"],"owner":{"repo":"north","path":"profiles/tom/skills/build-vs-reuse/SKILL.md"}}],
      "activationPaths": []
    },
    {
      "id": "north-session-lifecycle",
      "kind": "hook",
      "title": "North session lifecycle",
      "triggerDescription": "Publish provider lifecycle telemetry.",
      "permission": "on",
      "active": true,
      "owner": {"repo": "north", "path": "profiles/tom/hooks/north-session-end.sh"},
      "members": [],
      "supports": ["assignments"],
      "distributions": [{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-on-spawn-codex"},"adapterId":"north-on-spawn-codex"}],
      "activationPaths": []
    }
  ],
  "projectionPlan": {}
}
JSON

cat >"$bin/north" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AGENTS_TEST_LOG"
[[ "${1:-} ${2:-}" == 'config agents' ]] || exit 97
shift 2
activation="$NORTH_AGENT_STATE_ROOT/current/activation.json"
case "${1:-}" in
  status)
    if [[ "${2:-}" == --json ]]; then
      cat "$activation"
    else
      printf '%s\n' 'Sets' '  coordination on' 'Skills' '  build-vs-reuse off' 'Hooks' '  north-session-lifecycle on'
    fi
    ;;
  inspect)
    [[ "${2:-}" == coordination ]] || exit 2
    if [[ "${3:-}" == --json ]]; then
      printf '%s\n' '{"id":"coordination","tree":["messages","threads","assignments"],"provenance":["root:coordination"]}'
    else
      printf '%s\n' 'coordination' '  messages' '  threads' '  assignments'
    fi
    ;;
  path)
    [[ "${2:-}" == build-vs-reuse ]] || exit 2
    printf '%s\n' "$AGENTS_TEST_OWNER/profiles/tom/skills/build-vs-reuse/SKILL.md"
    ;;
  on|off)
    action="$1"
    [[ "${2:-}" == build-vs-reuse ]] || exit 2
    python3 - "$activation" "$action" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
enabled = sys.argv[2] == "on"
for unit in data["units"]:
    if unit["id"] == "build-vs-reuse":
        unit["permission"] = "on" if enabled else "off"
        unit["active"] = enabled
path.write_text(json.dumps(data) + "\n")
PY
    printf 'generation fixture-generation-2: build-vs-reuse %s\n' "$action"
    ;;
  sync)
    printf '%s\n' 'generation fixture-generation-3: synced'
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$bin/north"

export AGENTS_NORTH_BIN="$bin/north"
export NORTH_AGENT_STATE_ROOT="$state"
export AGENTS_TEST_LOG="$log"
export AGENTS_TEST_OWNER="$scratch/north"
mkdir -p "$AGENTS_TEST_OWNER/profiles/tom/skills/build-vs-reuse"
printf '%s\n' '---' 'name: build-vs-reuse' '---' \
  >"$AGENTS_TEST_OWNER/profiles/tom/skills/build-vs-reuse/SKILL.md"

status_json="$($agents status --json)"
python3 - "$status_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert data["schema"] == "north.agent-activation/v1"
unit = next(item for item in data["units"] if item["id"] == "build-vs-reuse")
required = {
    "id", "kind", "title", "triggerDescription", "permission", "active",
    "owner", "members", "supports", "distributions", "activationPaths",
}
assert required <= unit.keys()
assert unit["owner"] == {
    "repo": "north",
    "path": "profiles/tom/skills/build-vs-reuse/SKILL.md",
}
PY

status_text="$($agents status)"
[[ "$status_text" == *$'Sets\n'*$'Skills\n'*$'Hooks\n'* ]]
[[ "$(printf '%s\n' "$status_text" | sed -n '/^Sets$/=;/^Skills$/=;/^Hooks$/=')" == $'1\n3\n5' ]]

[[ "$($agents path build-vs-reuse)" == \
  "$AGENTS_TEST_OWNER/profiles/tom/skills/build-vs-reuse/SKILL.md" ]]
inspect_json="$($agents inspect coordination --json)"
python3 - "$inspect_json" <<'PY'
import json
import sys

tree = json.loads(sys.argv[1])
assert tree["tree"] == ["messages", "threads", "assignments"]
assert tree["provenance"] == ["root:coordination"]
PY

$agents on build-vs-reuse >/dev/null
python3 - "$state/current/activation.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
unit = next(item for item in data["units"] if item["id"] == "build-vs-reuse")
assert unit["permission"] == "on" and unit["active"] is True
PY

$agents off build-vs-reuse >/dev/null
[[ "$($agents sync)" == 'generation fixture-generation-3: synced' ]]

expected_calls=$'config agents status --json\nconfig agents status\nconfig agents path build-vs-reuse\nconfig agents inspect coordination --json\nconfig agents on build-vs-reuse\nconfig agents off build-vs-reuse\nconfig agents sync'
[[ "$(<"$log")" == "$expected_calls" ]]

before="$(wc -l <"$log")"
if "$agents" apply >/dev/null 2>"$scratch/apply.err"; then
  printf 'legacy apply command unexpectedly succeeded\n' >&2
  exit 1
fi
[[ "$(wc -l <"$log")" == "$before" ]]
grep -Fq 'usage: agents' "$scratch/apply.err"

if rg -q 'SKILLS=|HOOKS=|skill_source|modules[.]d|manifest[.]conf|activity[.]conf|apply[)]' "$agents"; then
  printf 'thin client contains retired activation-engine vocabulary\n' >&2
  exit 1
fi

printf 'agents thin client: North routing, set inspection, and build-vs-reuse projection PASS\n'
