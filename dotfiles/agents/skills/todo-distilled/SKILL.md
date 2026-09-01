---
name: todo-distilled
description: >-
  Use when work must survive the current turn or process: an external wait,
  handoff, parked task, or live lane/process another run must recover. An
  ordinary in-turn delegation or recoverable worktree does not trigger this
  skill. Maintains restart-grade Markdown + TOML records in the flat ~/code/todo/
  directory and the acknowledged agent-coord.md mailbox protocol. Also use
  when the operator says start, commence, or do the cross-supervisor protocol.
---

# Todo continuity, distilled

`~/code/todo/` is the flat inventory of live work whose ownership and recovery
must survive a restart. Create or update a record before the first mutation
only when work intentionally spans turns, waits externally, is handed off, or
leaves a live lane/process that another run could not safely reconstruct from
Git and the current conversation. Do not create continuity to document an
ordinary in-turn delegation, worktree, plan, phase, or status report.

## Hard boundaries and decisions

- Use one Markdown file with TOML front matter per independently resumable
  unit. Do not nest records or create a `main/` directory. Reserve
  `AGENTS.md` and `agent-coord.md` as singletons.
- Record exact owners, dependencies, conversation IDs, and every live lane.
  Paths are `repo:path` inside repositories and `~`-anchored for runtime and
  worktree locations.
- When a continuity record is independently required and execution begins,
  give that resumable execution one `[[attempt]]`. Include forecast or staffing
  facts only when those facts were actually needed; unknown evidence stays
  explicit and is never inferred.
- Record the concrete model identity observed for each run and review. A model
  field never records lineage, ambient, or selection behavior such as `self`,
  `parent`, `default`, or `auto`; recover the exact identity from run or
  dispatch evidence, and record an evidence gap outside the model field.
- Update at every visible phase boundary by replacing stale state, not appending
  a transcript. A successor must be able to execute `Next actions` directly.
- The product owner closes an existing durable record directly from terminal
  evidence. North separately settles the concrete run's process, delivery,
  driver, and parent/child state through `agent-run-lifecycle-distilled`.
- A mailbox `OPEN` or transport `RECEIVED` transfers no ownership. Use a
  separate acknowledged `work-ownership-v1` transition when ownership changes.
- Delete a record only when no continuity, dependent update, owned change,
  cleanup disposition, or awaited acknowledgement remains.

## Cross-supervisor protocol

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

## Minimum record workflow

1. Choose the narrowest true shape and create the record with required identity,
   lifecycle, owner, and outcome fields.
2. Add only the dependency, conversation, coordination, lane, and attempt facts
   needed to resume the durable unit.
3. Maintain current checkpoint, load-bearing decisions, executable next steps,
   observed verification, and recovery/cleanup conditions.
4. At terminal work, update the durable record directly from the fixed terminal
   facts after North has settled the concrete run state.
5. Land or explicitly dispose of the live state the record owns, update actual
   dependents, then remove the record when recovery value is gone.

Peer receipt invocation, exact line grammar, failure behavior, and record
schemas live in the reference skill; load it only when those details are
needed, per the always-loaded policy.
