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
channel=pair-eddecd5c3b94426f0519da031476a3c6e6499ed6e326d5eeafcf8cbbbf126037
future=$(( $(date +%s) * 1000 + 60000 ))
printf '%s\n' \
  '# mailbox fixture' \
  "- [2026-01-01T00:00:00.000Z][$channel][beta:/root -> alpha:/root][OPEN] event=stale-event session=stale-session round=1 proof=stale-proof expires=1 message=stale" \
  "- [2026-01-01T00:00:00.000Z][$channel][alpha:/root -> alpha:/root][OPEN] event=local-event session=local-session round=1 proof=local-proof expires=$future message=local" \
  "- [2026-01-01T00:00:00.000Z][$channel][outsider:/root -> alpha:/root][OPEN] event=direction-event session=direction-session round=1 proof=direction-proof expires=$future message=wrong-direction" \
  "- [2026-01-01T00:00:00.000Z][pair-wrong][beta:/root -> alpha:/root][OPEN] event=wrong-pair-event session=wrong-pair-session round=1 proof=wrong-pair-proof expires=$future message=wrong-pair" \
  "- [2026-01-01T00:00:00.000Z][$channel][beta:/root -> alpha:/root][OPEN] event=malformed-event missing-required-fields" \
  "- [2026-01-01T00:00:00.000Z][$channel][beta:/root -> alpha:/root][RECEIVED] event=wrong-proof-event reply-to=unknown-open session=wrong-proof-session round=1 proof=wrong-proof received-session=unknown-session" \
  "- [2026-01-01T00:00:00.000Z][$channel][beta:/root -> alpha:/root][OPEN] event=duplicate-event session=old-session round=1 proof=duplicate-proof expires=$future message=duplicate" \
  "- [2026-01-01T00:00:00.000Z][$channel][beta:/root -> alpha:/root][OPEN] event=duplicate-event session=old-session round=1 proof=duplicate-proof expires=$future message=duplicate" \
  "- [2026-01-01T00:00:00.000Z][$channel][alpha:/root -> beta:/root][RECEIVED] event=prior-receipt reply-to=duplicate-event session=prior-session round=1 proof=duplicate-proof received-session=old-session" \
  >"$mailbox"
initial_lines=$(wc -l <"$mailbox")

bun "$scratch/cross-supervisor-mailbox.mjs" duplex \
  --mailbox "$mailbox" \
  --local alpha:/root \
  --peer beta:/root \
  --message 'alpha requests Clause ownership summary' \
  --timeout-ms 10000 \
  >"$scratch/alpha.out" 2>"$scratch/alpha.err" &
alpha_pid=$!

# Real roots do not start simultaneously. Alpha must remain event-armed while
# beta is absent, and beta must later accept alpha's unexpired baseline OPEN.
sleep 0.2
kill -0 "$alpha_pid"
grep -Fq "ARMED channel=$channel local=alpha:/root peer=beta:/root" "$scratch/alpha.err"
grep -Fq 'rounds=2' "$scratch/alpha.err"

bun "$scratch/cross-supervisor-mailbox.mjs" duplex \
  --mailbox "$mailbox" \
  --local beta:/root \
  --peer alpha:/root \
  --message 'beta reports live Clause lane status' \
  --timeout-ms 10000 \
  >"$scratch/beta.out" 2>"$scratch/beta.err" &
beta_pid=$!

wait "$alpha_pid"
alpha_pid=
wait "$beta_pid"
beta_pid=

bun - "$mailbox" "$scratch/alpha.out" "$scratch/beta.out" "$channel" <<'JS'
import { readFileSync } from 'node:fs';

const [mailboxPath, alphaPath, betaPath, expectedChannel] = Bun.argv.slice(2);
const mailbox = readFileSync(mailboxPath, 'utf8');
const readDeliveries = path => readFileSync(path, 'utf8').trim().split('\n').map(JSON.parse);
const alpha = readDeliveries(alphaPath);
const beta = readDeliveries(betaPath);
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

for (const [name, deliveries, peer, message] of [
  ['alpha', alpha, 'beta:/root', 'beta reports live Clause lane status'],
  ['beta', beta, 'alpha:/root', 'alpha requests Clause ownership summary'],
]) {
  assert(deliveries.length === 2, `${name} did not receive two rounds`);
  assert(deliveries[0].round === 1 && deliveries[1].round === 2,
    `${name} rounds were not ordered`);
  for (const delivery of deliveries) {
    assert(delivery.channel === expectedChannel, `${name} derived a different pair channel`);
    assert(delivery.peerMessage === message, `${name} did not receive the exact peer message`);
    assert(delivery.peerOpen.includes(`[${peer} -> ${name}:/root][OPEN]`),
      `${name} did not receive the exact peer OPEN route`);
    assert(delivery.peerOpen.endsWith(`message=${message}`),
      `${name} peer OPEN omitted the message payload`);
    assert(mailbox.includes(`${delivery.peerOpen}\n`),
      `${name} peer OPEN was not delivered unchanged`);
    assert(delivery.receipt.includes(`[${peer} -> ${name}:/root][RECEIVED]`),
      `${name} did not receive a neutral transport receipt`);
    assert(mailbox.includes(`${delivery.receipt}\n`),
      `${name} receipt was not delivered unchanged`);
    assert(!/\]\[(ACK|PING)\]/.test(JSON.stringify(delivery)),
      `${name} delivery manufactured semantic acceptance`);
  }
}
JS

grep -Fq 'ROUND-COMPLETE round=2' "$scratch/alpha.err"
grep -Fq 'ROUND-COMPLETE round=2' "$scratch/beta.err"
grep -Fq 'REARMED round=2' "$scratch/alpha.err"
grep -Fq 'REARMED round=2' "$scratch/beta.err"

final_lines=$(wc -l <"$mailbox")
[[ $((final_lines - initial_lines)) -eq 8 ]]
[[ $(grep -c 'reply-to=duplicate-event' "$mailbox") -eq 1 ]]
generated="$scratch/generated-mailbox-lines"
tail -n "+$((initial_lines + 1))" "$mailbox" >"$generated"
[[ $(grep -c '\]\[OPEN\] ' "$generated") -eq 4 ]]
[[ $(grep -c '\]\[RECEIVED\] ' "$generated") -eq 4 ]]
! grep -Eq '\]\[(ACK|PING)\]' "$generated"
for ignored in stale-event local-event direction-event wrong-pair-event \
  malformed-event duplicate-event wrong-proof-event; do
  ! grep -Fq "$ignored" "$scratch/alpha.out"
  ! grep -Fq "$ignored" "$scratch/beta.out"
done

printf 'cross-supervisor-mailbox fixture: PASS (stable pair channel, staggered roots, two exact payload rounds, neutral receipts, rejection family)\n'
