#!/usr/bin/env bash
# SubagentStop teardown fixtures: a background shell whose output file a live
# process still holds blocks with the TaskStop message; the same shell stopped
# with TaskStop, completed (notification), or with no process holding its
# output allows; a live Monitor blocks and an expired one allows; no
# background tasks, an unreadable transcript and stop_hook_active allow.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/subagent-teardown.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/subagent-teardown-test.XXXXXX")"
sleeper=""
trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; rm -rf "${SCRATCH:?}"' EXIT
ACTIVATION="$SCRATCH/activation.active"
printf 'hook subagent-teardown\n' >"$ACTIVATION"
OUT="$SCRATCH/tasks/bshell001.output"
mkdir -p "$SCRATCH/tasks" "$SCRATCH/subagents"
: >"$OUT"
now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

shell_start='{"type":"assistant","timestamp":"'"$now"'","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_sh","name":"Bash","input":{"command":"sleep 600","description":"Long soak run","run_in_background":true}}]}}
{"type":"user","timestamp":"'"$now"'","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_sh","content":"Command running in background with ID: bshell001. Output is being written to: '"$OUT"'. You will be notified when it completes."}]},"toolUseResult":{"stdout":"","stderr":"","backgroundTaskId":"bshell001"}}'
taskstop='{"type":"assistant","timestamp":"'"$now"'","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_stop","name":"TaskStop","input":{"task_id":"bshell001"}}]}}'
completed='{"type":"attachment","timestamp":"'"$now"'","attachment":{"type":"queued_command","prompt":"<task-notification>\n<task-id>bshell001</task-id>\n<status>completed</status>\n</task-notification>"}}'
monitor_at() {
  printf '%s\n' '{"type":"assistant","timestamp":"'"$1"'","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mon","name":"Monitor","input":{"command":"tail -f x","description":"CI watch","timeout_ms":600000}}]}}' \
    '{"type":"user","timestamp":"'"$1"'","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_mon","content":"Monitor started (task bmon0001, expires in 10m)."}]},"toolUseResult":{"taskId":"bmon0001","timeoutMs":600000,"persistent":false}}'
}
plain='{"type":"assistant","timestamp":"'"$now"'","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ls","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","timestamp":"'"$now"'","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ls","content":"a b"}]},"toolUseResult":{"stdout":"a b","stderr":""}}'

fixture() { printf '%s\n' "$2" >"$SCRATCH/subagents/agent-$1.jsonl"; printf '%s' "$SCRATCH/subagents/agent-$1.jsonl"; }
stop_input() { printf '{"session_id":"s","hook_event_name":"SubagentStop","agent_id":"a1","agent_type":"worker","stop_hook_active":%s,"transcript_path":"%s/main.jsonl","agent_transcript_path":"%s"}' "${2:-false}" "$SCRATCH" "$1"; }
call() {
  printf '%s' "$1" | env -u AGENT_NO_AUTHORING_HOOKS NORTH_AGENT_ACTIVE="$ACTIVATION" \
    NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$HOOK"
}

pass=0 fail=0
check() {
  if [ "$1" = ok ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$2"
  else fail=$((fail + 1)); printf 'FAIL  %s\n      out=%s\n' "$2" "$3"; fi
}
expect_allow() { local out; out="$(call "$1")"; [ -z "$out" ] && check ok "$2" || check bad "$2" "$out"; }
expect_block() {
  local out; out="$(call "$1")"
  [ "$(printf '%s' "$out" | jq -r .reason 2>/dev/null)" = "$3" ] \
    && [ "$(printf '%s' "$out" | jq -r .decision 2>/dev/null)" = block ] \
    && check ok "$2" || check bad "$2" "$out"
}
shell_msg='You still have background tasks running: bshell001 (Long soak run). Stop each with TaskStop, then finish your report.'

sleep 60 >>"$OUT" &
sleeper=$!
running="$(fixture running "$shell_start")"
start=$(date +%s%N)
expect_block "$(stop_input "$running")" 'background shell still running blocks with the TaskStop message' "$shell_msg"
ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$ms" -lt 1000 ] && check ok "block decision takes ${ms} ms (under 1000)" || check bad 'block decision under 1000 ms' "${ms} ms"
expect_allow "$(stop_input "$running" true)" 'stop_hook_active true allows a still-running shell'
expect_allow "$(stop_input "$(fixture stopped "$shell_start
$taskstop")")" 'shell stopped with TaskStop allows'
expect_allow "$(stop_input "$(fixture completed "$shell_start
$completed")")" 'shell with a completion notification allows'
expect_block "$(stop_input "$(fixture monitor "$(monitor_at "$now")")")" 'live Monitor blocks' \
  'You still have background tasks running: bmon0001 (CI watch). Stop each with TaskStop, then finish your report.'
expect_allow "$(stop_input "$(fixture expired "$(monitor_at 2020-01-01T00:00:00.000Z)")")" 'Monitor past its timeout allows'
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
expect_allow "$(stop_input "$running")" 'shell whose output no process holds allows'
expect_allow "$(stop_input "$(fixture plain "$plain")")" 'no background tasks allows'
expect_allow "$(stop_input "$SCRATCH/subagents/missing.jsonl")" 'unreadable transcript allows'

printf 'subagent-teardown: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
