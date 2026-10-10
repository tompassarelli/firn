#!/usr/bin/env bash
# Fixtures for the lead regrounding hook: the main session's first Agent spawn
# gets the CronCreate instruction, its second spawn and any subagent's spawn
# get nothing.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/lead-regrounding.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/lead-regrounding-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
ACTIVATION="$SCRATCH/activation.active"
printf 'hook lead-regrounding\n' >"$ACTIVATION"

# call SESSION [AGENT_ID]: print the hook's additionalContext ("" when silent).
call() {
  local input
  input="$(python3 -c '
import json, sys
d = {"session_id": sys.argv[1], "transcript_path": "/dev/null", "hook_event_name": "PostToolUse",
     "tool_name": "Agent", "tool_input": {"description": "w", "prompt": "p", "subagent_type": "worker"},
     "tool_response": {"status": "async_launched"}}
if sys.argv[2]:
    d.update(agent_id=sys.argv[2], agent_type="worker")
print(json.dumps(d))' "$1" "${2:-}")"
  printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" \
    NORTH_AGENT_ACTIVE="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 \
    "$HOOK" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw else "")'
}

pass=0 fail=0
check() {
  if [ "$1" = ok ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail + 1)); printf 'FAIL  %s\n      out=%s\n' "$2" "$3"; fi
}

out="$(call s1)"
case "$out" in
  *CronList*CronCreate*'3,13,23,33,43,53 * * * *'*'[routine:tick] Run `agents routines show tick` and follow it.'*'threads unowned'*'spawn gate'*'tick=<n>'*'CronDelete'*) check ok 'main session first spawn gets the tick pointer, CronList guard and its current text' ;;
  *) check bad 'main session first spawn gets the tick pointer, CronList guard and its current text' "$out" ;;
esac
out="$(call s1)"
[ -z "$out" ] && check ok 'main session second spawn is silent' || check bad 'main session second spawn is silent' "$out"
out="$(call s2 a1)"
[ -z "$out" ] && check ok 'subagent spawn is silent' || check bad 'subagent spawn is silent' "$out"

printf 'lead-regrounding: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
