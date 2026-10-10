#!/usr/bin/env bash
# Deny/pass matrix for the worker wait guard: a worker's foreground command that
# can block past 60 s is denied; background runs, short commands and non-workers pass.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/worker-wait-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/worker-wait-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"
printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"worker-wait-guard","kind":"hook","category":"agents","permission":"on","active":true}]}\n' >"$ACTIVATION"

pass=0 fail=0
# run EXPECT DESCRIPTION AGENT_TYPE BACKGROUND TIMEOUT_MS COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" agent="$3" bg="$4" to="$5" cmd="$6"; shift 6
  local input out decision ok=0
  input="$(python3 -c 'import json,sys
ti = {"command": sys.argv[1]}
if sys.argv[3] == "1": ti["run_in_background"] = True
if sys.argv[4]: ti["timeout"] = int(sys.argv[4])
d = {"tool_name": "Bash", "tool_input": ti}
if sys.argv[2]: d["agent_type"] = sys.argv[2]
print(json.dumps(d))' "$cmd" "$agent" "$bg" "$to")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" \
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
run deny  'until/sleep wait'        worker      0 ''     'until grep -q done f; do sleep 20; done'
run deny  'safe-push foreground'    worker      0 ''     'timeout 900 safe-push --to main'
run deny  'leased run foreground'   worker-high 0 ''     "$MC run --owner o --timeout-seconds 600 -- bun wisp view s o"
run deny  'long timeout field'      worker      0 300000 'bun run check'
run deny  'full suite'              worker      0 ''     'bun run test'
run deny  'long sleep'              worker      0 ''     'sleep 120'
run deny  'ci watch'                worker      0 ''     'gh run watch 123'
run allow 'background safe-push'    worker      1 ''     'safe-push --to main'
run allow 'background wait'         worker      1 600000 'until grep -q done f; do sleep 20; done'
run allow 'short command'           worker      0 30000  'git status'
run allow 'single test file'        worker      0 ''     'bun test test/a.test.ts'
run allow 'short sleep'             worker      0 ''     'sleep 5'
run allow 'lead session'            ''          0 ''     'until x; do sleep 30; done'
run allow 'other agent type'        Explore     0 ''     'safe-push --to main'
run allow 'killswitch'              worker      0 ''     'safe-push --to main' AGENT_NO_AUTHORING_HOOKS=1
run deny  'safe-push bare'          worker      0 ''     'safe-push --to main'
run deny  'safe-push after cd'      worker      0 ''     'cd x && safe-push --to main'
run deny  'safe-push env prefix'    worker      0 ''     'FOO=1 safe-push'
run allow 'which safe-push'         worker      0 ''     'which safe-push'
run allow 'command -v in subst'     worker      0 ''     'wc -l $(command -v safe-push)'
run allow 'quoted safe-push'        worker      0 ''     'git commit -m "land through safe-push"'
HEREDOC=$'git commit -F - <<\'EOF\'\nsafe-push lands it\nEOF'
run allow 'heredoc body safe-push'  worker      0 ''     "$HEREDOC"
printf '{"tool_name":"Bash"' | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" "$HOOK" && pass=$((pass + 1))

printf 'worker-wait-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
