#!/usr/bin/env bash
# Fixture transcripts for the worker handoff hook: workers at 400k+ get the
# handoff text with their note path, repeated once per further 50k; workers
# below 400k, other agent types and the main session get nothing.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/worker-handoff.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/worker-handoff-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
ACTIVATION="$SCRATCH/activation.json"
HANDOFFS="$SCRATCH/home/.local/state/agents/handoffs"

set_active() {
  local permission=off
  [ "$1" = true ] && permission=on
  printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"worker-handoff","kind":"hook","category":"agents","permission":"%s","active":%s}]}\n' "$permission" "$1" >"$ACTIVATION"
}
set_active true

# transcript FILE TOKENS: a worker transcript whose last assistant turn used TOKENS
# of context, followed by a tool result larger than the hook's first read window.
transcript() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, tokens = sys.argv[1], int(sys.argv[2])
lines = [
    {"type": "user", "message": {"role": "user", "content": "brief"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "old"}],
     "usage": {"input_tokens": 9, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 0}}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}],
     "usage": {"input_tokens": 1000, "cache_read_input_tokens": tokens - 3000, "cache_creation_input_tokens": 2000}}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "x" * 300000}]}},
    {"type": "attachment", "attachment": {"type": "total_tokens_reminder"}},
]
with open(path, "w") as f:
    for line in lines:
        f.write(json.dumps(line) + "\n")
PY
}

# call AGENT_ID AGENT_TYPE TOKENS: print the hook's additionalContext ("" when silent).
call() {
  local id="$1" type="$2" tokens="$3" file="$SCRATCH/agent-$1.jsonl" input
  transcript "$file" "$tokens"
  input="$(python3 -c '
import json, sys
d = {"session_id": "s", "transcript_path": "/dev/null", "hook_event_name": "PostToolUse",
     "tool_name": "Bash", "tool_input": {"command": "true"}, "tool_response": {"stdout": ""}}
if sys.argv[2]:
    d.update(agent_id=sys.argv[1], agent_type=sys.argv[2], agent_transcript_path=sys.argv[3])
print(json.dumps(d))' "$id" "$type" "$file")"
  printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" \
    NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 \
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
expect_handoff() {
  local out note="$HANDOFFS/$1.md"
  out="$(call "$1" "$2" "$3")"
  case "$out" in
    *"$note"*"HANDOFF $note"*) check ok "$4" ;;
    *) check bad "$4" "$out" ;;
  esac
}
expect_silent() {
  local out
  out="$(call "$1" "$2" "$3")"
  if [ -z "$out" ]; then check ok "$4"; else check bad "$4" "$out"; fi
}

expect_handoff a1 worker-high 410000 'worker at 410k gets the handoff text with its path'
expect_silent a1 worker-high 430000 'second call at 430k is silent'
expect_handoff a1 worker-high 460000 'reminder at 460k'
expect_silent a1 worker-high 480000 'no reminder at 480k'
expect_silent a2 worker 390000 'worker at 390k is silent'
expect_handoff a3 worker 400000 'plain worker at exactly 400k gets the handoff text'
expect_silent a4 Explore 900000 'Explore agent is silent'
expect_silent a5 '' 900000 'main session (no agent_type) is silent'
set_active false
expect_silent a6 worker-high 900000 'inactive hook is silent'
set_active true

out="$(printf '{not json "agent_type":"worker' | HOME="$SCRATCH/home" \
  NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$HOOK")"
[ -z "$out" ] && check ok 'malformed input is silent' || check bad 'malformed input is silent' "$out"

printf 'worker-handoff: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
