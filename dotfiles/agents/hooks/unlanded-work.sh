#!/usr/bin/env bash
# Claude Code SessionStart hook: one line naming how many unlanded lanes
# (worktrees or branches with work not on origin/main) are older than 24 h in
# the hourly lane-gc report, so an agent continues one instead of redoing it.
set -uo pipefail

report="${LANE_GC_UNLANDED:-$HOME/.local/state/agents/lane-gc/unlanded.txt}"
[ -r "$report" ] || exit 0
count="$(awk -F'\t' '!/^#/ && $1+0 >= 24 { n++ } END { print n+0 }' "$report")"
[ "$count" -gt 0 ] || exit 0
printf '%s unlanded worktrees/branches older than 24 h are listed in %s (lane-gc --unlanded). Before starting an issue, continue an existing lane that references it instead of starting over.\n' \
  "$count" "${report/#$HOME/\~}"
