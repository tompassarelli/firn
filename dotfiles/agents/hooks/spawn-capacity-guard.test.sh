#!/usr/bin/env bash
# Spawn gate fixtures over a fake capacity probe: provisioned CPUs under the
# limit allow a local worker, at or over it (or protected pressure above 20)
# deny with the queue/farm/cloud message, high system PSI with few provisioned
# CPUs allows, an unreadable probe allows, a remote worker allows, and an URGENT
# brief passes and is logged. The Codex spawn_agent path through the behavior
# decider denies the same way. Delegation budget 0 (session env, or a subagent
# brief without a Delegation line) denies with the do-it-yourself message and
# budget 1 allows; a domain below the first in the project priority stops at 80%.
# A fresh usage-gate.json refusal (firn#12 money gate) denies with its own text.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/spawn-capacity-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/spawn-capacity-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
export AGENT_HOOK_ERRORS="$SCRATCH/errors.tsv"
ACTIVATION="$SCRATCH/activation.active"
STATUS="$SCRATCH/probe.json"
printf 'hook spawn-capacity-guard\nhook codex-behavior-guard\n' >"$ACTIVATION"
mkdir -p "$SCRATCH/home/.claude/projects/p/s/subagents"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-a.jsonl"
: >"$SCRATCH/home/.claude/projects/p/s/subagents/agent-b.jsonl"
GATE="$SCRATCH/home/.local/state/agents/usage-gate.json"
mkdir -p "${GATE%/*}"
# gate CLAUDE_REFUSAL: write a fresh money-gate verdict (codex always allowed).
gate() { printf '{"claude":{"epoch":%s,"stale_min":30,"refusal":%s},"codex":{"epoch":%s,"stale_min":30,"refusal":null}}\n' "$(date +%s)" "$1" "$(date +%s)" >"$GATE"; }
gate null

# status LEASED PROTECTED [SYSTEM_PSI]: write the probe fixture (limit 20 CPUs).
status() { printf '{"decision":"RUN","leasedBatchCpus":%s,"leasedNativeCpus":12,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":%s,"cpuSomeAvg10":%s}\n' "$1" "$2" "${3:-1}" >"$STATUS"; }

# call HOOK JSON: print the deny reason ("" when allowed).
call() {
  printf '%s' "$2" | env -u AGENT_NO_AUTHORING_HOOKS -u AGENT_ROLE -u AGENT_DELEGATION_BUDGET -u AGENT_ORG_NAME \
    AGENTS_ORG_FILE="$SCRATCH/org.json" AGENTS_ORCHESTRATION="$SCRATCH/orchestration.toml" "${CALL_ENV[@]}" HOME="$SCRATCH/home" SPAWN_CAPACITY_HOME="$SCRATCH/home" \
    SPAWN_CAPACITY_STATUS="$STATUS" CODEX_BEHAVIOR_STATE="$SCRATCH/state" \
    CODEX_BEHAVIOR_CODE_ROOT="$SCRATCH/code" \
    NORTH_AGENT_ACTIVE="$ACTIVATION" NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 \
    "$1" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"].get("permissionDecisionReason", "") if raw else "")'
}
agent() { printf '{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":%s}' "$1"; }

pass=0 fail=0
CALL_ENV=()
check() {
  if [ "$1" = ok ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail + 1)); printf 'FAIL  %s\n      out=%s\n' "$2" "$3"; fi
}
expect_allow() { local out; out="$(call "$HOOK" "$1")"; [ -z "$out" ] && check ok "$2" || check bad "$2" "$out"; }
expect_deny() {
  local out; out="$(call "${3:-$HOOK}" "$1")"
  case "$out" in
    "Capacity leases and unleased heavy load commit ${DENY_LEASED:-24} of the 20 CPUs the machine can hand out, protected desktop pressure is ${DENY_PROTECTED:-5}% (limit 20%), and 2 local workers are running. Queue this worker until a lease ends, send heavy checks to the farm, or use a cloud worker for code-only work (cloud-workers skill). Workers already running are unaffected."*) check ok "$2" ;;
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
printf '{"decision":"RUN","leasedBatchCpus":10,"committedBatchCpus":21,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":5}\n' >"$STATUS"
DENY_LEASED=21 expect_deny "$(agent "$worker")" 'measured lease use plus unleased heavy load past the limit denies'
printf '{"decision":"RUN","leasedBatchCpus":24,"committedBatchCpus":19,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":5}\n' >"$STATUS"
expect_allow "$(agent "$worker")" 'committed CPUs, when reported, replace reserved ones'
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
expect_allow "$(agent '{"subagent_type":"worker-haiku","prompt":"[routine:watchdog] Run `agents routines show watchdog` and follow it."}')" 'the capacity watchdog brief is exempt over the limit'
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

status 10 5
dodeny() { local out; out="$(call "$HOOK" "$1")"; case "$out" in "Your delegation budget is 0 ("*"Do this work directly yourself"*) check ok "$2" ;; *) check bad "$2" "$out" ;; esac; }
CALL_ENV=(AGENT_DELEGATION_BUDGET=0); dodeny "$(agent "$worker")" 'session budget 0 denies with the do-it-yourself message'
CALL_ENV=(AGENT_DELEGATION_BUDGET=0); dodeny "$(agent '{"subagent_type":"claude-code-guide","isolation":"remote","prompt":"p"}')" 'budget 0 denies remote and non-worker spawns too'
CALL_ENV=(AGENT_DELEGATION_BUDGET=1); expect_allow "$(agent "$worker")" 'session budget 1 allows'
CALL_ENV=(AGENT_ROLE=worker); dodeny "$(agent "$worker")" 'role worker without a budget defaults to 0'
CALL_ENV=()
sub="$SCRATCH/home/.claude/projects/p/s/subagents"
printf '{"type":"user","message":{"role":"user","content":"Item: x. Do it."}}\n' >"$sub/agent-w0.jsonl"
printf '{"type":"user","message":{"role":"user","content":"Delegation: role=sub-lead depth=2 budget=1\\nItem: x."}}\n' >"$sub/agent-w1.jsonl"
subagent() { printf '{"session_id":"s","transcript_path":"%s","agent_id":"%s","agent_type":"worker","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":%s}' "$SCRATCH/home/.claude/projects/p/s.jsonl" "$1" "$worker"; }
dodeny "$(subagent w0)" 'a subagent whose brief has no Delegation line is a worker and is denied'
expect_allow "$(subagent w1)" 'a subagent briefed with budget=1 may spawn'
printf '{"version":1,"nodes":[{"id":"sc","domain":"Smashcraft"},{"id":"mu","domain":"galileo"}]}\n' >"$SCRATCH/org.json"
cat >"$SCRATCH/orchestration.toml" <<'TOML'
[projects.galileo]
priority = 1
[projects.smashcraft]
priority = 2
TOML
status 17 5
out="$(CALL_ENV=(AGENT_ORG_NAME=sc); call "$HOOK" "$(agent "$worker")")"
case "$out" in "Domain smashcraft ranks below galileo"*) check ok 'a lower-priority domain stops at 80% of the limit' ;; *) check bad 'a lower-priority domain stops at 80% of the limit' "$out" ;; esac
CALL_ENV=(AGENT_ORG_NAME=mu); expect_allow "$(agent "$worker")" 'the first-priority domain keeps the headroom'
CALL_ENV=()

status 19 5
input="$(agent "$worker")"
status 2 5
gate '"No: a new claude worker could spend money: test."'
out="$(call "$HOOK" "$(agent "$worker")")"
[ "$out" = "No: a new claude worker could spend money: test." ] && check ok 'fresh money-gate refusal denies' || check bad 'fresh money-gate refusal denies' "$out"
gate null

start=$(date +%s%N)
printf '%s' "$input" | env -u AGENT_DELEGATION_BUDGET -u AGENT_ROLE AGENT_ORG_NAME=mu \
  AGENTS_ORG_FILE="$SCRATCH/org.json" AGENTS_ORCHESTRATION="$SCRATCH/orchestration.toml" \
  SPAWN_CAPACITY_HOME="$SCRATCH/home" SPAWN_CAPACITY_STATUS="$STATUS" NORTH_AGENT_ACTIVE="$ACTIVATION" "$HOOK" >/dev/null
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$ms" -lt 100 ] && check ok "allow decision takes ${ms} ms (under 100)" || check bad 'allow decision under 100 ms' "${ms} ms"

printf 'spawn-capacity-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
