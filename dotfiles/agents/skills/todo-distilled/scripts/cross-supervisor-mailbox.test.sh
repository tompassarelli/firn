#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/cross-supervisor-mailbox-test.XXXXXX")
watcher_pid=
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$watcher_pid" ]] && kill -0 "$watcher_pid" 2>/dev/null; then
    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
  fi
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'cross-supervisor-mailbox test: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

"$here/build-cross-supervisor-mailbox" "$scratch/cross-supervisor-mailbox.mjs"
cmp -- "$here/cross-supervisor-mailbox.mjs" "$scratch/cross-supervisor-mailbox.mjs"

mailbox="$scratch/agent-coord.md"
printf '# mailbox fixture\n' >"$mailbox"
bun "$scratch/cross-supervisor-mailbox.mjs" open-watch \
  --mailbox "$mailbox" \
  --coordination C-FOCUSED \
  --sender codex:/root \
  --receiver peer:/root \
  --status ACK \
  --timeout-ms 10000 \
  --proof proof-focused \
  --message 'focused handshake' \
  >"$scratch/watch.out" 2>"$scratch/watch.err" &
watcher_pid=$!

for _ in $(seq 1 100); do
  grep -q '^ARMED ' "$scratch/watch.err" 2>/dev/null && break
  sleep 0.02
done
grep -q '^ARMED ' "$scratch/watch.err"

bun "$scratch/cross-supervisor-mailbox.mjs" reply \
  --mailbox "$mailbox" \
  --coordination C-FOCUSED \
  --sender codex:/root \
  --receiver peer:/root \
  --status ACK \
  --proof proof-focused \
  --message 'local direction must be ignored' \
  >"$scratch/local.out"
bun "$scratch/cross-supervisor-mailbox.mjs" reply \
  --mailbox "$mailbox" \
  --coordination C-FOCUSED \
  --sender peer:/root \
  --receiver codex:/root \
  --status ACK \
  --proof proof-wrong \
  --message 'wrong proof must be ignored' \
  >"$scratch/wrong-proof.out"
sleep 0.05
kill -0 "$watcher_pid"
[[ ! -s "$scratch/watch.out" ]]

bun "$scratch/cross-supervisor-mailbox.mjs" reply \
  --mailbox "$mailbox" \
  --coordination C-FOCUSED \
  --sender peer:/root \
  --receiver codex:/root \
  --status ACK \
  --proof proof-focused \
  --message 'peer receipt' \
  >"$scratch/matching.out"
wait "$watcher_pid"
watcher_pid=

cmp -- "$scratch/matching.out" "$scratch/watch.out"
[[ $(wc -l <"$scratch/watch.out") -eq 1 ]]
grep -Fq '[C-FOCUSED][peer:/root -> codex:/root][ACK]' "$scratch/watch.out"
grep -Fq 'proof=proof-focused peer receipt' "$scratch/watch.out"
grep -Fq '[C-FOCUSED][codex:/root -> peer:/root][OPEN]' "$mailbox"

printf 'cross-supervisor-mailbox fixture: PASS (peer match; local and wrong proof ignored)\n'
