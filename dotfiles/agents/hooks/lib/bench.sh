#!/usr/bin/env bash
# Run one provider event's wired hooks concurrently, as Claude and Codex do,
# and report wall and CPU (user+sys) p50/p95 per event, plus the activation
# gate's own p50. Take a machine-capacity exclusive lease for comparable runs.
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
usage: bench.sh [--settings FILE] [--matcher NAME] [--tool NAME] [--hooks-dir DIR]
                [--runs N] [--command CMD] [--gate-runs N]
  --settings   Claude settings JSON with .hooks.PreToolUse (default ~/.claude/settings.json)
  --matcher    PreToolUse matcher entry to run, verbatim (default Bash)
  --tool       tool_name in the payload (default: the matcher)
  --hooks-dir  replace the installed ~/.agents/hooks/ with this directory (e.g. a worktree)
  --runs       events to time (default 30)
  --command    Bash command in the benign payload (default "ls -la")
  --gate-runs  activation gate calls to time (default 50, 0 skips)
EOF
}

settings="$HOME/.claude/settings.json"
matcher=Bash
tool=''
hooks_dir=''
runs=30
command='ls -la'
gate_runs=50
while (($#)); do
  case "$1" in
    --settings) settings="$2"; shift 2 ;;
    --matcher) matcher="$2"; shift 2 ;;
    --tool) tool="$2"; shift 2 ;;
    --hooks-dir) hooks_dir="${2%/}"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --command) command="$2"; shift 2 ;;
    --gate-runs) gate_runs="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

mapfile -t hooks < <(jq -r --arg m "$matcher" \
  '.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[].command' "$settings")
((${#hooks[@]})) || { echo "bench: no PreToolUse hooks for matcher $matcher in $settings" >&2; exit 2; }
if [[ -n "$hooks_dir" ]]; then
  hooks=("${hooks[@]//"$HOME/.agents/hooks"/$hooks_dir}")
fi

payload="$(jq -cn --arg c "$command" --arg cwd "$PWD" --arg t "${tool:-$matcher}" \
  '{session_id:"bench",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:$t,tool_input:{command:$c}}')"

scratch="$(mktemp -d)"
trap 'rm -rf -- "${scratch:?}"' EXIT

one_event() {
  local h pid status
  local -a pids=()
  for h in "${hooks[@]}"; do
    bash -c "$h" <<<"$payload" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    status=0
    wait "$pid" || status=$?
    ((status == 0 || status == 2)) || { echo "bench: a hook exited $status; sample rejected" >&2; exit 1; }
  done
}

TIMEFORMAT='%R %U %S'
one_event
for ((i = 0; i < runs; i++)); do
  { time one_event; } 2>>"$scratch/times"
done

pct() {
  sort -n | awk -v p="$1" '{v[NR] = $1} END {i = int((NR - 1) * p + 0.5) + 1; printf "%.1f", v[i] * 1000}'
}
wall50="$(awk '{print $1}' "$scratch/times" | pct 0.5)"
wall95="$(awk '{print $1}' "$scratch/times" | pct 0.95)"
cpu50="$(awk '{print $2 + $3}' "$scratch/times" | pct 0.5)"
cpu95="$(awk '{print $2 + $3}' "$scratch/times" | pct 0.95)"
printf 'hooks=%d runs=%d wall_ms p50=%s p95=%s cpu_ms p50=%s p95=%s\n' \
  "${#hooks[@]}" "$runs" "$wall50" "$wall95" "$cpu50" "$cpu95"

if ((gate_runs > 0)); then
  lib="${hooks_dir:-$HOME/.agents/hooks}/lib/north-agent-activation.sh"
  [[ -r "$lib" ]] || lib="${hooks_dir:-$HOME/.agents/hooks}/../lib/north-agent-activation.sh"
  (
    # shellcheck source=/dev/null
    . "$lib"
    for ((i = 0; i < gate_runs; i++)); do
      s=$EPOCHREALTIME
      north_agent_unit_active hook git-stash-guard || true
      e=$EPOCHREALTIME
      echo "$s $e"
    done
  ) | awk '{print $2 - $1}' >"$scratch/gate"
  printf 'gate runs=%d p50_ms=%s\n' "$gate_runs" "$(pct 0.5 <"$scratch/gate")"
fi
