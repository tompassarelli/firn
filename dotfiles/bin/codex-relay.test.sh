#!/usr/bin/env bash
# A message the session's hook picks up is never pasted; an empty one is refused.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
state="$(mktemp -d)"
trap 'rm -rf "$state"' EXIT
(sleep 2; rm -f "$state/relay-s1.txt") &
out="$(echo hello | CODEX_BEHAVIOR_STATE="$state" RELAY_WAIT=10 "$here/codex-relay" s1 999999)"
[ "$out" = "delivered by hook" ] || { echo "FAIL hook path: $out"; exit 1; }
if echo "" | CODEX_BEHAVIOR_STATE="$state" "$here/codex-relay" s1 999999 2>/dev/null; then
  echo "FAIL empty message accepted"
  exit 1
fi
echo "codex-relay: 2 passed"
