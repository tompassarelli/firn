# Cross-supervisor transport

## Contract and limits

This is the operator-invoked mailbox protocol, not routine delegation
bookkeeping. It establishes bidirectional receipt and a live listener.
Receipt is not agreement, instruction acceptance, or work ownership.
The helper owns event identities and mailbox writes; agents convey its evidence.

## Procedure

When the operator invokes the cross-supervisor protocol:

1. Identify this root supervisor, the peer root supervisor, the shared concern,
   and each non-overlapping execution lane. The exact root identities determine
   one stable pair channel in either startup order; the concern remains message
   payload and never becomes a guessed coordination ID.
2. Admit one named monitor per root. Each monitor independently runs the same
   duplex helper once, with `--local` and `--peer` set from its own perspective.
   Resolve the helper beside the authoritative `SKILL.md` already read for this
   invocation; do not rediscover it through `agents path` or a projection:

   ```bash
   # todo_skill_dir is the directory containing the authoritative SKILL.md.
   bun "$todo_skill_dir/scripts/cross-supervisor-mailbox.mjs" duplex \
     --mailbox ~/code/todo/agent-coord.md \
     --local "codex:/root" \
     --peer "peer:/root" \
     --message "synchronize the shared concern"
   ```

   The defaults are two rounds and 300000 milliseconds. Never ask the operator
   to relay a channel, mailbox line, event, token, or pending message between
   roots. The helper derives the channel from the exact root pair, generates
   every event, timestamp, session, and proof, and owns all mailbox writes.
3. The duplex helper registers one bounded file-event subscription, emits its
   local `OPEN`, discovers an exact live peer `OPEN`, writes the corresponding
   neutral `RECEIVED` with the peer proof, matches the peer receipt to its own
   `OPEN`, and rearms for the requested initial rounds. After successful local
   delivery it writes one correlated `SETTLED` marker and remains event-armed
   and quiescent. A bounded renewal with the same exact local payload reads that
   marker and emits no new `OPEN`; a changed local payload emits one `OPEN`.
   A changed peer payload wakes the quiescent helper, receives one `RECEIVED`,
   and is delivered once. It subscribes before publishing and accepts an
   unexpired, previously unanswered peer `OPEN` already present at arm time, so
   either root may start first. It ignores stale, local, wrong-direction,
   wrong-pair, wrong-proof, malformed, duplicate, and unchanged peer events. It
   never polls and is not a daemon. `RECEIVED` proves transport only; it never
   accepts a claim, decision, instruction, or work transfer.
4. On the stderr `ARMED` line, the monitor native-delivers the armed state to
   its root. Each stdout JSON line contains the exact peer `OPEN`, its message
   payload, and its correlated neutral receipt; native-deliver it unchanged.
   `QUIESCENT` means the same helper remains event-armed without writing. Report
   `synced` only after naming the delivered peer event and receipt plus evidence
   that the next round or quiescent helper is armed. Do not infer semantic
   agreement from transport completion.
5. Do not re-invoke after `QUIESCENT`; the current bounded helper is already the
   listener. At its normal `QUIESCENT-TIMEOUT`, re-invoke the same command. The
   completed `SETTLED` marker makes unchanged renewal quiescent without mailbox
   writes, while a newly supplied local payload announces once. Stop and reap
   the exact helper when the concern is settled.
6. A pre-quiescence timeout or watch failure is not wake proof. Report its exact
   diagnostic, keep the handshake pending, and continue unrelated product work.
   A manual or transcript read never substitutes for the event path.

Never create a second incident authority or competing repair lane. The mailbox
coordinates intentions and evidence; acknowledged work ownership remains a
separate `work-ownership-v1` transition.

## Why these distinctions matter

Subscribing before publishing handles either startup order. Proof-correlated
receipts reject an old or wrong-direction message without treating it as a new
request. A settled marker makes unchanged renewal quiet; a changed payload is
the event that warrants another delivery.

Keep one monitor per root and one helper per monitor. Polling, manually copying
mailbox lines, or asking the operator to relay tokens cannot prove the event
path works. A transport fault leaves the handshake pending, not the product
task blocked. Stop and reap the owned helper when the concern is finished.
