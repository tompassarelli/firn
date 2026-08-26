---
name: todo-distilled
description: >-
  Use whenever work could remain in flight: before creating a worktree,
  delegating a lane, waiting on another actor, writing a handoff, or parking a
  thread, plan, task, project, or resource. Maintains restart-grade Markdown +
  TOML records in the flat ~/code/todo/ directory and the acknowledged
  agent-coord.md mailbox protocol.
---

# Todo continuity, distilled

`~/code/todo/` is the flat inventory of live work whose ownership and recovery
must survive a restart. Create or update a record before the first mutation
when work creates a lane, delegates, waits externally, spans responses, or has
more than one independently useful phase.

## Hard boundaries and decisions

- Use one Markdown file with TOML front matter per independently resumable
  unit. Do not nest records or create a `main/` directory. Reserve
  `AGENTS.md` and `agent-coord.md` as singletons.
- Record exact owners, dependencies, conversation IDs, and every live lane.
  Paths are `repo:path` inside repositories and `~`-anchored for runtime and
  worktree locations.
- Give every active task/project execution one `[[attempt]]` before work begins,
  including forecast and staffing facts. Settle the same attempt with observed
  actuals; unknown evidence stays explicit and is never inferred.
- Update at every visible phase boundary by replacing stale state, not appending
  a transcript. A successor must be able to execute `Next actions` directly.
- The product owner decides integration, verification, review, publication,
  debt, and lane disposition before issuing one immutable SettlementCard.
  A settler may apply only that exact bookkeeping envelope.
- A mailbox `OPEN` transfers no ownership until the addressed receiver writes
  `ACK` and a live bounded monitor delivers it.
- Delete a record only when no continuity, dependent update, owned change,
  cleanup disposition, or awaited acknowledgement remains.

## Minimum record workflow

1. Choose the narrowest true shape and create the record with required identity,
   lifecycle, owner, and outcome fields.
2. Add exact dependency/conversation/coordination/lane facts when present and
   one attempt for active execution.
3. Maintain current checkpoint, load-bearing decisions, executable next steps,
   observed verification, and recovery/cleanup conditions.
4. At terminal work, record actuals and evidence through the owner-approved
   settlement contract and deterministic estimate receipt.
5. Land or explicitly dispose of owned lanes, settle coordination, update
   dependents, then remove the record when recovery value is gone.

Complete schema and mailbox details live in the reference skill; load it only
for an explicit request or a named unresolved detail, per the always-loaded
policy.
