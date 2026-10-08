#!/usr/bin/env bash
# Spawn gate fixtures over a fake capacity probe: provisioned CPUs under the
# limit allow a local worker, at or over it (or protected pressure above 20)
# deny with the queue/farm/cloud message, high system PSI with few provisioned
# CPUs allows, an unreadable probe allows, a remote worker allows, and an URGENT
# brief passes and is logged. The Codex spawn_agent path through the behavior
# decider denies the same way.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/spawn-capacity-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/spawn-capacity-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
ACTIVATION="$SCRATCH/activation.json"
STATUS="$SCRATCH/probe.json"
printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"spawn-capacity-guard","kind":"hook","category":"agents","permission":"on","active":true},{"id":"codex-behavior-guard","kind":"hook","category":"authoring","permission":"on","active":true}]}\n' >"$ACTIVATION"
mkdir -p "$SCRATCH/home/.claude/projects/p/s/subagents"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-a.jsonl"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-b.jsonl"

# status LEASED PROTECTED [SYSTEM_PSI]: write the probe fixture (limit 20 CPUs).
status() { printf '{"decision":"RUN","leasedBatchCpus":%s,"leasedNativeCpus":12,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":%s,"cpuSomeAvg10":%s}\n' "$1" "$2" "${3:-1}" >"$STATUS"; }

# call HOOK JSON: print the deny reason ("" when allowed).
call() {
  printf '%s' "$2" | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" SPAWN_CAPACITY_HOME="$SCRATCH/home" \
    SPAWN_CAPACITY_STATUS="$STATUS" CODEX_BEHAVIOR_STATE="$SCRATCH/state" \
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
    "Capacity leases hold ${DENY_LEASED:-24} of the 20 CPUs the machine can hand out, protected desktop pressure is ${DENY_PROTECTED:-5}% (limit 20%), and 2 local workers are running. Queue this worker until a lease ends, send heavy checks to the farm, or use a cloud worker for code-only work (cloud-workers skill). Workers already running are unaffected."*) check ok "$2" ;;
    *) check bad "$2" "$out" ;;
  esac
}

worker='{"subagent_type":"worker","description":"d","prompt":"do it"}'
status 19 5
expect_allow "$(agent "$worker")" '19 of 20 provisioned CPUs allows a local worker'
status 2 5 95
expect_allow "$(agent "$worker")" 'system PSI 95 with 2 provisioned CPUs allows a local worker'
status 20 5
DENY_LEASED=20 expect_deny "$(agent "$worker")" '20 of 20 provisioned CPUs (at the limit) denies with the message'
status 4 20.5
DENY_LEASED=4 DENY_PROTECTED=20.5 expect_deny "$(agent "$worker")" 'protected pressure 20.5 denies with few provisioned CPUs'
status 4 20
expect_allow "$(agent "$worker")" 'protected pressure exactly 20 allows'
printf '{"decision":"RUN","profile":"unattended","leasedBatchCpus":4,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":40}\n' >"$STATUS"
expect_allow "$(agent "$worker")" 'unattended profile (Tom away) skips the protected-pressure refusal, as the helper does'
printf '{"decision":"RUN","profile":"unattended","leasedBatchCpus":20,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":40}\n' >"$STATUS"
DENY_LEASED=20 DENY_PROTECTED=0 expect_deny "$(agent "$worker")" 'unattended profile still denies at the provisioned limit'
status 24 5
expect_deny "$(agent "$worker")" '24 of 20 provisioned CPUs (over the limit) denies with the message'
expect_deny "$(agent '{"description":"d","prompt":"p"}')" 'omitted subagent_type (general-purpose) is local and denied'
expect_allow "$(agent '{"subagent_type":"worker","isolation":"remote","prompt":"p"}')" 'remote worker allows over the limit'
expect_allow "$(agent '{"subagent_type":"claude-code-guide","prompt":"p"}')" 'non-worker agent type allows'
expect_allow "$(agent '{"subagent_type":"worker","prompt":"CASE=URGENT FACT=\"prod login is down for every user\" fix it"}')" 'URGENT brief passes over the limit'
grep -q '"gate": "spawn-capacity"' "$SCRATCH/state/verify-overrides.jsonl" 2>/dev/null \
  && check ok 'URGENT override is logged' || check bad 'URGENT override is logged' "no log line"
expect_deny "$(agent '{"subagent_type":"worker","prompt":"CASE=URGENT FACT=\"short\" go"}')" 'URGENT with a too-short fact is denied'
rm -f "$STATUS"
expect_allow "$(agent "$worker")" 'missing probe output allows'
printf 'machine-capacity: shared admission lock remained busy\n' >"$STATUS"
expect_allow "$(agent "$worker")" 'unreadable probe output allows'
printf '{"decision":"RUN"}\n' >"$STATUS"
expect_allow "$(agent "$worker")" 'probe output without lease fields allows'
status 24 5
expect_deny '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"fix the bug and land it"}}' \
  'Codex spawn_agent over the limit denies through the behavior guard' "$HERE/codex-behavior-guard.sh"
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":"{\\"items\\":[{\\"type\\":\\"text\\",\\"text\\":\\"CASE=URGENT FACT=\\\\\\"main red blocks every landing (#242)\\\\\\" fix it\\"}]}"}')"
[ -z "$out" ] && check ok 'Codex URGENT inside serialized JSON items allows' || check bad 'Codex URGENT inside serialized JSON items allows' "$out"
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"CASE=URGENT FACT=\"main red blocks every landing (#242)\" fix it"}}')"
[ -z "$out" ] && check ok 'Codex URGENT in message allows' || check bad 'Codex URGENT in message allows' "$out"
enc='{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"collaborationspawn_agent","tool_input":{"message":"gAAAAABqx6PNencrypted","name":"hellfire_base_293_high","model":"gpt-6.1-sol","reasoning_effort":"high"}}'
out="$(call "$HERE/codex-behavior-guard.sh" "$enc")"
[ -n "$out" ] && check ok 'encrypted Codex spawn without a spawn-urgent line is denied' || check bad 'encrypted Codex spawn without a spawn-urgent line is denied' "allowed"
mkdir -p "$SCRATCH/home/.local/state/agents"
printf '%s\thellfire_base_293_high\tmain red blocks every landing (#242)\n' "$(date +%s)" >"$SCRATCH/home/.local/state/agents/spawn-urgent.tsv"
out="$(call "$HERE/codex-behavior-guard.sh" "$enc")"
[ -z "$out" ] && check ok 'encrypted Codex spawn named in a fresh spawn-urgent line allows' || check bad 'encrypted Codex spawn named in a fresh spawn-urgent line allows' "$out"
printf '%s\thellfire_base_293_high\tmain red blocks every landing (#242)\n' "$(( $(date +%s) - 1000 ))" >"$SCRATCH/home/.local/state/agents/spawn-urgent.tsv"
out="$(call "$HERE/codex-behavior-guard.sh" "$enc")"
[ -n "$out" ] && check ok 'a spawn-urgent line older than 15 minutes is denied' || check bad 'a spawn-urgent line older than 15 minutes is denied' "allowed"
status 10 5
out="$(call "$HERE/codex-behavior-guard.sh" '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"message":"fix the bug and land it"}}')"
[ -z "$out" ] && check ok 'Codex spawn_agent under the limit allows' || check bad 'Codex spawn_agent under the limit allows' "$out"

status 19 5
input="$(agent "$worker")"
start=$(date +%s%N)
printf '%s' "$input" | env SPAWN_CAPACITY_STATUS="$STATUS" NORTH_AGENT_ACTIVATION="$ACTIVATION" "$HOOK" >/dev/null
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$ms" -lt 100 ] && check ok "allow decision takes ${ms} ms (under 100)" || check bad 'allow decision under 100 ms' "${ms} ms"

printf 'spawn-capacity-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
