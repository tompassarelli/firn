#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/cross-supervisor-mailbox-test.XXXXXX")
alpha_pid=
beta_pid=
cleanup() {
  local status=$?
  trap - EXIT
  for pid in "$alpha_pid" "$beta_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
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
future=$(( $(date +%s) * 1000 + 60000 ))
printf '%s\n' \
  '# mailbox fixture' \
  '- [2026-01-01T00:00:00.000Z][C-DUPLEX][beta:/root -> alpha:/root][OPEN] event=stale-event session=stale-session round=1 proof=stale-proof expires=1 stale' \
  "- [2026-01-01T00:00:00.000Z][C-DUPLEX][alpha:/root -> alpha:/root][OPEN] event=local-event session=local-session round=1 proof=local-proof expires=$future local" \
  "- [2026-01-01T00:00:00.000Z][C-DUPLEX][outsider:/root -> alpha:/root][OPEN] event=direction-event session=direction-session round=1 proof=direction-proof expires=$future wrong-direction" \
  '- [2026-01-01T00:00:00.000Z][C-DUPLEX][beta:/root -> alpha:/root][ACK] event=wrong-token-event reply-to=unknown-open session=wrong-token-session round=1 proof=wrong-token received' \
  '- [2026-01-01T00:00:00.000Z][C-DUPLEX][beta:/root -> alpha:/root][OPEN] event=malformed-event missing-required-fields' \
  "- [2026-01-01T00:00:00.000Z][C-DUPLEX][beta:/root -> alpha:/root][OPEN] event=duplicate-event session=old-session round=1 proof=duplicate-proof expires=$future duplicate" \
  "- [2026-01-01T00:00:00.000Z][C-DUPLEX][beta:/root -> alpha:/root][OPEN] event=duplicate-event session=old-session round=1 proof=duplicate-proof expires=$future duplicate" \
  '- [2026-01-01T00:00:00.000Z][C-DUPLEX][alpha:/root -> beta:/root][ACK] event=prior-receipt reply-to=duplicate-event session=prior-session round=1 proof=duplicate-proof already-replied' \
  >"$mailbox"
initial_lines=$(wc -l <"$mailbox")

bun "$scratch/cross-supervisor-mailbox.mjs" duplex \
  --mailbox "$mailbox" \
  --coordination C-DUPLEX \
  --local alpha:/root \
  --peer beta:/root \
  --status ACK \
  --timeout-ms 10000 \
  --rounds 2 \
  --message 'duplex fixture' \
  >"$scratch/alpha.out" 2>"$scratch/alpha.err" &
alpha_pid=$!

for _ in $(seq 1 100); do
  grep -q '^ARMED ' "$scratch/alpha.err" 2>/dev/null && break
  sleep 0.02
done
grep -q '^ARMED ' "$scratch/alpha.err"

bun "$scratch/cross-supervisor-mailbox.mjs" duplex \
  --mailbox "$mailbox" \
  --coordination C-DUPLEX \
  --local beta:/root \
  --peer alpha:/root \
  --status ACK \
  --timeout-ms 10000 \
  --rounds 2 \
  --message 'duplex fixture' \
  >"$scratch/beta.out" 2>"$scratch/beta.err" &
beta_pid=$!

wait "$alpha_pid"
alpha_pid=
wait "$beta_pid"
beta_pid=

[[ $(wc -l <"$scratch/alpha.out") -eq 2 ]]
[[ $(wc -l <"$scratch/beta.out") -eq 2 ]]
grep -F '[C-DUPLEX][beta:/root -> alpha:/root][ACK]' "$scratch/alpha.out" >/dev/null
grep -F '[C-DUPLEX][alpha:/root -> beta:/root][ACK]' "$scratch/beta.out" >/dev/null
grep -Fq 'ROUND-COMPLETE round=2' "$scratch/alpha.err"
grep -Fq 'ROUND-COMPLETE round=2' "$scratch/beta.err"
grep -Fq 'REARMED round=2' "$scratch/alpha.err"
grep -Fq 'REARMED round=2' "$scratch/beta.err"

final_lines=$(wc -l <"$mailbox")
[[ $((final_lines - initial_lines)) -eq 8 ]]
[[ $(grep -c 'reply-to=duplicate-event' "$mailbox") -eq 1 ]]
! grep -Fq 'stale-event' "$scratch/alpha.out"
! grep -Fq 'local-event' "$scratch/alpha.out"
! grep -Fq 'direction-event' "$scratch/alpha.out"
! grep -Fq 'wrong-token-event' "$scratch/alpha.out"
! grep -Fq 'malformed-event' "$scratch/alpha.out"
! grep -Fq 'duplicate-event' "$scratch/alpha.out"

printf 'cross-supervisor-mailbox fixture: PASS (two processes, two duplex rounds, stale/local/direction/token/malformed/duplicate ignored)\n'
