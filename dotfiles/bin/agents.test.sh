#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
agents="$repo/dotfiles/bin/agents"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agents-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

mkdir -p "$scratch/bin"
cat >"$scratch/bin/north" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AGENTS_TEST_LOG"
[[ "${1:-} ${2:-}" == "config agents" ]] || exit 97
shift 2
case "${1:-}" in
  status) printf '%s\n' 'fixture status' ;;
  inspect) printf 'fixture inspect %s\n' "${2:-}" ;;
  path) printf '/fixture/%s/SKILL.md\n' "${2:-}" ;;
  on|off) printf 'fixture %s %s\n' "$1" "${2:-}" ;;
  sync) printf '%s\n' 'fixture sync' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$scratch/bin/north"

export AGENTS_NORTH_BIN="$scratch/bin/north"
export AGENTS_TEST_LOG="$scratch/calls"

[[ "$($agents status --json)" == 'fixture status' ]]
[[ "$($agents inspect clause-authoring --json)" == \
  'fixture inspect clause-authoring' ]]
[[ "$($agents path clause-authoring)" == \
  '/fixture/clause-authoring/SKILL.md' ]]
[[ "$($agents on clause-authoring)" == \
  'fixture on clause-authoring' ]]
[[ "$($agents off clause-authoring)" == \
  'fixture off clause-authoring' ]]
[[ "$($agents sync)" == 'fixture sync' ]]

expected=$'config agents status --json\nconfig agents inspect clause-authoring --json\nconfig agents path clause-authoring\nconfig agents on clause-authoring\nconfig agents off clause-authoring\nconfig agents sync'
[[ "$(<"$AGENTS_TEST_LOG")" == "$expected" ]]

if AGENTS_NORTH_BIN="$scratch/bin/missing" "$agents" status \
  >"$scratch/missing.out" 2>"$scratch/missing.err"; then
  printf 'agents accepted a missing North CLI\n' >&2
  exit 1
fi
grep -Fq 'agents: North CLI is unavailable' "$scratch/missing.err"

printf 'ok: agents is a thin North CLI client\n'
