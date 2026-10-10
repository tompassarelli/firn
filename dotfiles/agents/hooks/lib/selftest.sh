#!/usr/bin/env bash
# Send one deny and one pass fixture through every installed guard on each
# provider path, exactly as the providers launch them, and report per guard.
# Exit 1 when an installed, active guard misses either verdict.
set -uo pipefail

usage() {
  echo "usage: selftest.sh [DIR...]   (default: /etc/codex/hooks ~/.agents/hooks)"
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
dirs=("$@")
((${#dirs[@]})) || dirs=(/etc/codex/hooks "$HOME/.agents/hooks")

runtime=/etc/codex/hooks/runtime
scratch="$(mktemp -d)"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/todo" "$scratch/state" "$scratch/tripwire"
printf '{"decision":"RUN","leasedBatchCpus":1,"leasedNativeCpus":0,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":0,"cpuSomeAvg10":0}\n' >"$scratch/capacity"
printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=1\n' >"$scratch/pressure"
code="$HOME/code"

bash_event() { jq -cn --arg c "$1" --arg a "${2:-}" --arg cwd "$scratch" \
  '{session_id:"selftest",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}
   + (if $a == "" then {} else {agent_type:$a,agent_id:"selftest"} end)'; }
write_event() { jq -cn --arg p "$1" --arg t "$2" --arg cwd "$scratch" \
  '{session_id:"selftest",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$p,content:$t}}'; }
agent_event() { jq -cn --arg tool "$1" --arg s "$2" --arg p "$3" --arg cwd "$scratch" \
  '{session_id:"selftest",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:$tool,
    tool_input:{subagent_type:$s,description:"selftest",prompt:$p,message:$p}}'; }

fixtures() {
  case "$1" in
    git-stash-guard) bash_event 'git stash'; bash_event 'git stash push -m selftest' ;;
    git-blind-stage-guard) bash_event 'git add -A'; bash_event 'git add README.md' ;;
    heavy-command-guard) bash_event 'cargo build'; bash_event 'cargo check' ;;
    worker-wait-guard) bash_event 'sleep 300' worker; bash_event 'sleep 1' worker ;;
    native-launch-guard) bash_event 'wine game.exe'; bash_event 'ls game.exe' ;;
    modern-search-guard) bash_event 'grep -r selftest .'; bash_event 'rg selftest .' ;;
    resource-safe-search-guard) bash_event 'rg selftest /proc'; bash_event 'rg selftest .' ;;
    session-kill-guard) bash_event 'kill -9 -1'; bash_event 'kill -0 1' ;;
    tripwire-guard) bash_event 'rm -rf /'; bash_event 'rm -f selftest.tmp' ;;
    corpus-scan-guard) bash_event "rg selftest $code/north-data"; bash_event 'rg selftest .' ;;
    launch-critical-worktree-guard)
      write_event "$code/nixos-config/main/selftest.tmp" x; write_event "$scratch/selftest.tmp" x ;;
    concrete-model-identity-guard)
      write_event "$scratch/todo/task.md" 'model = "inherited"'
      write_event "$scratch/todo/task.md" 'model = "claude-opus-5-5"' ;;
    worker-tier-guard)
      agent_event Agent worker $'Item: rename a field.\nCategory: mechanical'
      agent_event Agent worker-haiku $'Item: rename a field.\nCategory: mechanical' ;;
    spawn-capacity-guard)
      agent_event Agent worker 'do it'; agent_event Agent worker 'do it' ;;
    codex-behavior-guard)
      agent_event spawn_agent worker 'A measure-only run of the bench.'
      agent_event spawn_agent worker 'Fix the parser and land it.' ;;
    *) return 1 ;;
  esac
}

verdict() {
  local hook="$1" event="$2" status_file="$3" out
  # Claude and Codex read exit 2 as a deny with the reason on stderr.
  out="$(printf '%s' "$event" | "$runtime/env" -u BASH_ENV -u ENV \
    PATH="$runtime:$HOME/.local/bin:/run/current-system/sw/bin" \
    NORTH_AGENT_PYTHON="$runtime/python3" TODO_ROOT="$scratch/todo" \
    TRIPWIRE_LOG_DIR="$scratch/tripwire" CODEX_BEHAVIOR_STATE="$scratch/state" \
    SPAWN_CAPACITY_STATUS="$status_file" SPAWN_CAPACITY_PRESSURE="$scratch/pressure" \
    "$runtime/bash" "$hook" 2>/dev/null)"
  [ $? -ne 2 ] || { echo deny; return; }
  jq -r '.hookSpecificOutput.permissionDecision // .decision // "pass"' <<<"${out:-{\}}" 2>/dev/null || echo malformed
}

[ -x "$runtime/bash" ] || { echo "selftest: missing $runtime/bash" >&2; exit 1; }
failed=0
for dir in "${dirs[@]}"; do
  for hook in "$dir"/*.sh; do
    [ -e "$hook" ] || continue
    id="${hook##*/}"; id="${id%.sh}"
    mapfile -t events < <(fixtures "$id") || true
    if ((${#events[@]} != 2)); then
      printf '%s\t%s\tno-fixture\n' "$dir" "$id"
      continue
    fi
    deny_status="$scratch/capacity"
    [ "$id" != spawn-capacity-guard ] || {
      printf '{"decision":"RUN","leasedBatchCpus":20,"leasedNativeCpus":0,"aggregateCpuLimit":20,"protectedCpuSomeAvg10":5,"cpuSomeAvg10":1}\n' >"$scratch/capacity-full"
      deny_status="$scratch/capacity-full"
    }
    d="$(verdict "$hook" "${events[0]}" "$deny_status")"
    p="$(verdict "$hook" "${events[1]}" "$scratch/capacity")"
    if [ "$d" = deny ] && [ "$p" = pass ]; then
      result=ok
    elif NORTH_HOOK_ID="$id" bash -c '. "$1" && ! authoring_guards_off' _ "${hook%/*}/lib/authoring-killswitch.sh" 2>/dev/null; then
      result=FAIL failed=1
    else
      result=inactive
    fi
    printf '%s\t%s\tdeny=%s pass=%s\t%s\n' "$dir" "$id" "$d" "$p" "$result"
  done
done
exit "$failed"
