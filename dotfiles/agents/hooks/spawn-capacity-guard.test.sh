#!/usr/bin/env bash
# Spawn gate fixtures: CPU pressure under the limit allows a local worker, at or
# over it denies with the queue/farm/cloud message, an unreadable pressure file
# allows, a remote worker allows, and an URGENT brief passes and is logged. The
# Codex spawn_agent path through the behavior decider denies the same way.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/spawn-capacity-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/spawn-capacity-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
ACTIVATION="$SCRATCH/activation.json"
PRESSURE="$SCRATCH/cpu"
printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"spawn-capacity-guard","kind":"hook","category":"agents","permission":"on","active":true},{"id":"codex-behavior-guard","kind":"hook","category":"authoring","permission":"on","active":true}]}\n' >"$ACTIVATION"
mkdir -p "$SCRATCH/home/.claude/projects/p/s/subagents"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-a.jsonl"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-b.jsonl"

pressure() { printf 'some avg10=1.00 avg60=%s avg300=1.00 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' "$1" >"$PRESSURE"; }

# call HOOK JSON: print the deny reason ("" when allowed).
call() {
  printf '%s' "$2" | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" SPAWN_CAPACITY_HOME="$SCRATCH/home" \
    SPAWN_CAPACITY_PRESSURE="$PRESSURE" CODEX_BEHAVIOR_STATE="$SCRATCH/state" \
    CODEX_BEHAVIOR_CODE_ROOT="$SCRATCH/code" \
    NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 \
    "$1" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"].get("permissionDecisionReason", "") if raw else "")'
}
agent() { printf '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":%s}' "$1"; }

pass=0 fail=0
check() {
  if [ "$1" = ok ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail + 1)); printf 'FAIL  %s\n      out=%s\n' "$2" "$3"; fi
}
expect_allow() { local out; out="$(call "$HOOK" "$1")"; [ -z "$out" ] && check ok "$2" || check bad "$2" "$out"; }
expect_deny() {
  local out; out="$(call "${3:-$HOOK}" "$1")"
  case "$out" in
    "The machine is at 55% CPU pressure (limit 40%) with 2 local workers running. Queue this worker until pressure falls, send heavy checks to the farm, or use a cloud worker for code-only work (cloud-workers skill). Workers already running are unaffected."*) check ok "$2" ;;
    *) check bad "$2" "$out" ;;
  esac
}

worker='{"subagent_type":"worker","description":"d","prompt":"do it"}'
pressure 39.99
expect_allow "$(agent "$worker")" 'pressure 39.99 under the limit allows a local worker'
pressure 55
expect_deny "$(agent "$worker")" 'pressure 55 over the limit denies a local worker with the message'
expect_deny "$(agent '{"description":"d","prompt":"p"}')" 'omitted subagent_type (general-purpose) is local and denied'
expect_allow "$(agent '{"subagent_type":"worker","isolation":"remote","prompt":"p"}')" 'remote worker allows at pressure 55'
expect_allow "$(agent '{"subagent_type":"claude-code-guide","prompt":"p"}')" 'non-worker agent type allows'
expect_allow "$(agent '{"subagent_type":"worker","prompt":"CASE=URGENT FACT=\"prod login is down for every user\" fix it"}')" 'URGENT brief passes at pressure 55'
grep -q '"gate": "spawn-capacity"' "$SCRATCH/state/verify-overrides.jsonl" 2>/dev/null \
  && check ok 'URGENT override is logged' || check bad 'URGENT override is logged' "no log line"
expect_deny "$(agent '{"subagent_type":"worker","prompt":"CASE=URGENT FACT=\"short\" go"}')" 'URGENT with a too-short fact is denied'
rm -f "$PRESSURE"
expect_allow "$(agent "$worker")" 'unreadable pressure file allows'
pressure 55
expect_deny '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"fix the bug and land it"}}' \
  'Codex spawn_agent over the limit denies through the behavior guard' "$HERE/codex-behavior-guard.sh"
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":"{\\"items\\":[{\\"type\\":\\"text\\",\\"text\\":\\"CASE=URGENT FACT=\\\\\\"main red blocks every landing (#242)\\\\\\" fix it\\"}]}"}')"
[ -z "$out" ] && check ok 'Codex URGENT inside serialized JSON items allows' || check bad 'Codex URGENT inside serialized JSON items allows' "$out"
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"CASE=URGENT FACT=\"main red blocks every landing (#242)\" fix it"}}')"
[ -z "$out" ] && check ok 'Codex URGENT in message allows' || check bad 'Codex URGENT in message allows' "$out"
pressure 10
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"fix the bug and land it"}}')"
[ -z "$out" ] && check ok 'Codex spawn_agent under the limit allows' || check bad 'Codex spawn_agent under the limit allows' "$out"

pressure 39.99
input="$(agent "$worker")"
start=$(date +%s%N)
printf '%s' "$input" | env SPAWN_CAPACITY_PRESSURE="$PRESSURE" NORTH_AGENT_ACTIVATION="$ACTIVATION" "$HOOK" >/dev/null
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$ms" -lt 100 ] && check ok "allow decision takes ${ms} ms (under 100)" || check bad 'allow decision under 100 ms' "${ms} ms"

printf 'spawn-capacity-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
