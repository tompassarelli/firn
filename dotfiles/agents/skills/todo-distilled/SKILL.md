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
- A mailbox `OPEN` transfers no ownership until the addressed receiver writes
  `ACK` and a live bounded monitor delivers it.
- Delete a record only when no continuity, dependent update, owned change,
  cleanup disposition, or awaited acknowledgement remains.

## Cross-supervisor protocol

When the operator invokes the cross-supervisor protocol:

1. Identify this root supervisor, the peer root supervisor, the one shared
   concern, each non-overlapping execution lane, and the exact mailbox item in
   `~/code/todo/agent-coord.md`.
2. Admit one named monitor and have it invoke the skill-owned Bun helper; do
   not ask the operator to compose a mailbox line or set up a watcher:

   ```bash
   todo_skill=$(dirname "$(agents path todo-distilled)")
   bun "$todo_skill/scripts/cross-supervisor-mailbox.mjs" open-watch \
     --mailbox ~/code/todo/agent-coord.md \
     --coordination C007 \
     --sender "codex:/root" \
     --receiver "peer:/root" \
     --status ACK \
     --timeout-ms 60000 \
     --message "acknowledge the shared concern"
   ```

   `open-watch` generates a unique event ID, timestamp, and fresh proof token,
   appends the addressed `OPEN`, registers a future file-event subscription,
   writes `ARMED` to stderr, and writes only the first matching peer `ACK` or
   `PING` line to stdout before exiting. The write transfers no ownership.
3. On `ARMED`, the monitor sends the armed state to this root through native
   collaboration. On the one stdout line, it native-delivers that exact line,
   then immediately invokes `open-watch` again with a fresh generated request
   while the concern remains live. This is the normal self-rearm path; each
   underlying watcher remains bounded and one-shot, with no polling or daemon.
4. Accept only an event authored by the exact peer, addressed to this root,
   with the requested status and proof. A local `OPEN`, wrong direction, wrong
   token, manual mailbox read, elapsed time, or the monitor's own write is not
   wake proof.
5. Report `synced` only after native delivery, naming the peer event ID and
   timestamp and confirming the next watcher is armed. If proof fails, report
   the exact monitor defect and keep the handshake pending while unrelated
   product work continues.
6. A receipt found before `ARMED` is a pre-arm race, not wake proof. The helper
   automatically appends a retry with a new event ID and proof token and rearms
   within the original timeout. Never reuse the old request after a manual read.
   Close the monitor when the shared concern is settled.

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
