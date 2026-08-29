---
name: todo-distilled
description: >-
  Use when work must survive the current turn or process: an external wait,
  handoff, parked task, or live lane/process another run must recover. An
  ordinary in-turn delegation or recoverable worktree does not trigger this
  skill. Maintains restart-grade Markdown + TOML records in the flat ~/code/todo/
  directory and the acknowledged agent-coord.md mailbox protocol.
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
- The product owner closes ordinary work directly from its terminal result.
  Issue a SettlementCard only when an existing durable todo, assignment, or
  coordination record needs terminal bookkeeping; a settler may apply only
  that exact envelope.
- A mailbox `OPEN` transfers no ownership until the addressed receiver writes
  `ACK` and a live bounded monitor delivers it.
- Delete a record only when no continuity, dependent update, owned change,
  cleanup disposition, or awaited acknowledgement remains.

## Minimum record workflow

1. Choose the narrowest true shape and create the record with required identity,
   lifecycle, owner, and outcome fields.
2. Add only the dependency, conversation, coordination, lane, and attempt facts
   needed to resume the durable unit.
3. Maintain current checkpoint, load-bearing decisions, executable next steps,
   observed verification, and recovery/cleanup conditions.
4. At terminal work, update the record directly unless an existing durable
   assignment or coordination consumer requires the settlement contract.
5. Land or explicitly dispose of the live state the record owns, update actual
   dependents, then remove the record when recovery value is gone.

Complete schema and mailbox details live in the reference skill; load it only
for an explicit request or a named unresolved detail, per the always-loaded
policy.
