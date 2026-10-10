#!/usr/bin/env bash
# Deny/pass matrix for the heavy command guard: heavy builds, full suites and
# headless renders outside machine-capacity run are denied; light neighbours pass.
set -uo pipefail
# Hooks run with the managed hook runtime first on PATH; so do their tests.
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/heavy-command-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/heavy-command-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.active"

pass=0 fail=0
set_active() {
  if [ "$1" = true ]; then printf 'hook heavy-command-guard\n' >"$ACTIVATION"; else : >"$ACTIVATION"; fi
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVE="$ACTIVATION" \
    NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$@" "$HOOK" 2>&1)"
  decision="$(python3 -c 'import json,sys
try:
    d = json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed"); raise SystemExit
print((d or {}).get("hookSpecificOutput", {}).get("permissionDecision", "silent"))' "${out:-}")"
  case "$expect" in
    deny)  [ "$decision" = deny ] && ok=1 ;;
    allow) [ "$decision" != deny ] && [ "$decision" != malformed ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-5s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-5s  %s\n      cmd=%q\n      decision=%s out=%s\n' "$expect" "$desc" "$cmd" "$decision" "$out"
  fi
}

MC='bun /opt/skills/machine-capacity/scripts/machine-capacity.mjs'
run deny  'cargo build'                'cargo build --release -j 6'
run deny  'full bun suite after cd'    'cd ts && bun test'
run allow 'project test runner admits itself' 'bun run test'
run deny  'wisp map build'             'bun wisp map build'
run deny  'headless render'            'bun wisp headless --render out --frames 3'
run deny  'wisp view'                  'bun wisp view scene out'
run deny  'timeout prefix'             'timeout 600 cargo build'
run allow 'leased cargo build'         "$MC run --owner o --timeout-seconds 600 -- cargo build --release"
run allow 'leased render'              "$MC run --class gpu --owner o --timeout-seconds 600 -- bun wisp view scene out"
run allow 'single test file'           'bun test test/a.test.ts'
run allow 'cargo check'                'cargo check'
run allow 'mention'                    'echo cargo build; rg "bun test" docs'
run allow 'map rebuild'                'bun wisp map rebuild'
run allow 'killswitch'                 'cargo build' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'inactive unit'              'cargo build'
printf '{"tool_name":"Bash"' | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" "$HOOK" && pass=$((pass + 1))

printf 'heavy-command-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
