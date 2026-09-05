# Cross-supervisor mailbox contract

## Transport versus ownership

An addressed receipt establishes delivery, not truth, agreement, instructions,
or accepted work. The run's ownership contract remains separate.
The operational invocation is in the todo-distilled cross-supervisor notes;
this file explains the wire and restart behavior, not a second implementation.

## Wire format and event ownership

One named monitor must watch `agent-coord.md`, deliver changes to its owner
within a bound, and be reaped with its supervisor. The helper derives
`PAIR-CHANNEL` as the full SHA-256 digest of the JSON-encoded, lexicographically
ordered exact root identities, prefixed with `pair-`. Prove the route with one
addressed transport round trip:

```text
- [timestamp][PAIR-CHANNEL][sender -> receiver][OPEN] event=EVENT session=SESSION round=N proof=TOKEN expires=MILLISECONDS message=EXACT-CONCERN
- [timestamp][PAIR-CHANNEL][receiver -> sender][RECEIVED] event=EVENT reply-to=OPEN-EVENT session=SESSION round=N proof=TOKEN received-session=OPEN-SESSION
- [timestamp][PAIR-CHANNEL][sender -> receiver][SETTLED] event=EVENT open=OPEN-EVENT session=SESSION proof=TOKEN message-sha256=DIGEST
```

Messages remain append-only while a concern is live. `RECEIVED` is a neutral
transport fact, never semantic acceptance or work acknowledgement. Use the
separate `work-ownership-v1` contract for ownership. On delivery timeout,
retain ownership and report the exact failure; the next bounded helper
invocation creates fresh events. Before stopping the monitor, settle every peer
payload already delivered to the root.

## Why renewal is quiet

Completed history needs ordered OPEN, correlated peer RECEIVED, and local
SETTLED with the exact payload digest. Only that triple suppresses an unchanged
local announcement on renewal. A changed local payload announces once; a changed
peer payload receives once. Mere matching text or an uncorrelated receipt is
not completed history.

The subscription precedes baseline capture so either root can start first.
Rejection of expired, wrong-pair, wrong-direction, malformed, duplicate, or
wrong-proof events prevents old mailbox content from becoming a fresh request.

## Reporting boundary

The root may report transport synced only after native delivery of the exact
peer event/receipt and evidence of a rearmed or quiescent listener. A manual
file read or successful helper launch does not prove this path. Pre-quiescence
timeout remains pending; unrelated product work continues.

## Helper implementation detail


Resolve the helper relative to the authoritative `SKILL.md` already read for
this invocation, never from a projection, remembered path, or a second
`agents path` lookup:

```bash
# todo_skill_dir is the directory containing that authoritative SKILL.md.
mailbox_helper="$todo_skill_dir/scripts/cross-supervisor-mailbox.mjs"
```

Each supervisor's named monitor starts one copy of the same command. `--local`
is that monitor's root and `--peer` is the other root; the peer runs the command
independently with those two values reversed:

```bash
bun "$mailbox_helper" duplex \
  --mailbox ~/code/todo/agent-coord.md \
  --local "codex:/root" \
  --peer "peer:/root" \
  --message "synchronize the shared concern"
```

The normal invocation has no operator-chosen coordination ID or status. The
helper derives one stable order-independent channel from the exact local/peer
pair. The shared concern remains `message=` payload. The helper generates its
local session, events, timestamps, proofs, and expiry, appends its `OPEN`,
discovers the peer's exact unexpired `OPEN`, and appends `RECEIVED` using that
peer event, proof, and session. It also watches for the exact `reply-to`, round,
proof, and receiving session matching its own `OPEN`. The operator must never
be asked to copy a channel, line, event, or token between roots.

After the peer receipt matches its own final initial `OPEN`, or its one changed
local `OPEN`, the helper appends `SETTLED` correlated to that open and proof.
The SHA-256 digest binds the exact delivered local payload without duplicating
it. Only an ordered local `OPEN` plus matching peer `RECEIVED` plus matching
local `SETTLED` establishes completed history. An uncorrelated receipt or marker
never suppresses delivery. On later invocation, an identical settled local
payload enters quiescence without an `OPEN`; a different local payload emits
one `OPEN` and settles after its receipt.

The subscription is installed before the baseline is captured. Baseline
discovery accepts only an exact, unexpired peer `OPEN` that this local root has
not previously answered. This makes either startup order safe while rejecting
expired or already-replied stale events. Current and future processing also
rejects a local route, another sender or receiver, another pair channel, a
receipt with the wrong `reply-to` or proof, malformed ordered fields, and
duplicate event IDs. Each peer `OPEN` receives at most one helper-owned receipt,
and each initial round delivers at most one peer `OPEN`. Once quiescent, an
unchanged peer payload emits nothing; one changed peer payload emits one
`RECEIVED`, one native delivery, and leaves the same helper quiescent.

`OPENED`, `ARMED`, `ROUND-COMPLETE`, `REARMED`, `SETTLED`, `QUIESCENT`,
`PEER-MESSAGE`, and `MESSAGE-RECEIVED` are diagnostics on stderr. Each stdout
line is one JSON object. `kind=duplex` carries the initial unchanged `peerOpen`,
parsed `peerMessage`, and correlated peer `receipt`; `kind=peer-message` carries
one changed peer payload and this helper's neutral receipt; and
`kind=message-received` carries the changed local open and peer receipt. The
named monitor sends `ARMED`, `QUIESCENT`, and every stdout delivery to its root
with the provider's native `send_message` operation. Only then may the root
report transport `synced`, naming the peer event and receipt and confirming the
next round or quiescent listener is armed. That claim never means the peer
accepted the message's semantics.

The defaults are two rounds and 300000 milliseconds. Explicit `--rounds` is
bounded from 1 through 32 and `--timeout-ms` from 1 through 300000. Completing
the initial rounds or changed delivery enters quiescence rather than exiting.
Normal quiescent timeout emits `QUIESCENT-TIMEOUT` and exits zero; timeout before
quiescence exits 124; argument, watch, or read failure exits 2. While the
concern remains live, the named monitor keeps the quiescent helper and
re-invokes only after its bounded zero exit. Completed history makes that
renewal write-free for an unchanged payload. The helper remains a bounded
file-event process with no polling, daemon, provider credential, manual mailbox
read, compatibility path, or transcript dependency.
