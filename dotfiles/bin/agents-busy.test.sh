#!/usr/bin/env bash
# Behavioural tests for dotfiles/bin/agents-busy against synthetic roots.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUSY="$ROOT/dotfiles/bin/agents-busy"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT
export AGENTS_BUSY_CODEX_ROOT="$fixture/codex" AGENTS_BUSY_CLAUDE_ROOT="$fixture/claude"
today="$fixture/codex/$(date +%Y/%m/%d)"
mkdir -p "$today" "$fixture/claude/-home-tom"

expect() { # expect <name> <0|1>
  local got=0
  "$BUSY" || got=$?
  if [ "$got" -ne "$2" ]; then printf 'FAIL %s: exit %s, want %s\n' "$1" "$got" "$2"; exit 1; fi
}

expect no-transcripts 1
touch -d '-20 minutes' "$today/rollout-old.jsonl" "$fixture/claude/-home-tom/old.jsonl"
expect only-stale-transcripts 1
touch "$today/rollout-live.jsonl"
expect live-codex-session 0
rm "$today/rollout-live.jsonl"
touch "$fixture/claude/-home-tom/live.jsonl"
expect live-claude-session 0
AGENTS_BUSY_MINUTES=0 expect zero-window 1
echo "agents-busy: all assertions passed"
