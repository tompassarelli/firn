#!/usr/bin/env bash
# Fixture transcripts for the worker handoff hook: workers at 200k+ get the
# handoff text with their note path, repeated once per further 50k; workers
# whose first transcript entry is 45+ minutes old get the leash text; workers
# below both, other agent types and the main session get nothing.
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

# transcript FILE TOKENS [MINUTES]: a worker transcript whose last assistant turn used
# TOKENS of context, followed by a tool result larger than the hook's first read
# window; with MINUTES its first entry is stamped that many minutes ago.
transcript() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
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
if sys.argv[3]:
    lines[0]["timestamp"] = (datetime.now(timezone.utc) - timedelta(minutes=int(sys.argv[3]))).isoformat().replace("+00:00", "Z")
with open(path, "w") as f:
    for line in lines:
        f.write(json.dumps(line) + "\n")
PY
}

# call AGENT_ID AGENT_TYPE TOKENS [MINUTES]: print the hook's additionalContext ("" when silent).
call() {
  local id="$1" type="$2" tokens="$3" file="$SCRATCH/agent-$1.jsonl" input
  transcript "$file" "$tokens" "${4:-}"
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
  out="$(call "$1" "$2" "$3" "${5:-}")"
  if [ -z "$out" ]; then check ok "$4"; else check bad "$4" "$out"; fi
}
expect_leash() {
  local out
  out="$(call "$1" "$2" 1000 "$3")"
  case "$out" in
    "You have run 45 minutes. Land anything that passes now"*"handoffs/<lane>.md"*"Not done:"*) check ok "$4" ;;
    *) check bad "$4" "$out" ;;
  esac
}

expect_handoff a1 worker-high 210000 'worker at 210k gets the handoff text with its path'
expect_silent a1 worker-high 230000 'second call at 230k is silent'
expect_handoff a1 worker-high 260000 'reminder at 260k'
expect_silent a1 worker-high 280000 'no reminder at 280k'
expect_silent a2 worker 190000 'worker at 190k is silent'
expect_handoff a3 worker 200000 'plain worker at exactly 200k gets the handoff text'
expect_silent a4 Explore 900000 'Explore agent is silent'
expect_silent a5 '' 900000 'main session (no agent_type) is silent'
expect_leash t1 worker 46 'worker whose first entry is 46 minutes old gets the leash text'
expect_silent t1 worker 1000 'leash repeat at 50 minutes is silent' 50
expect_leash t1 worker 56 'leash repeats at 56 minutes'
expect_silent t2 worker-haiku 1000 'worker at 44 minutes is silent' 44
expect_silent t3 Explore 1000 'Explore agent at 90 minutes is silent' 90
set_active false
expect_silent a6 worker-high 900000 'inactive hook is silent'
set_active true

out="$(printf '{not json "agent_type":"worker' | HOME="$SCRATCH/home" \
  NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$HOOK")"
[ -z "$out" ] && check ok 'malformed input is silent' || check bad 'malformed input is silent' "$out"

printf 'worker-handoff: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
