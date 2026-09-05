---
name: todo-distilled
description: >-
  Keep restart-grade records for cross-turn work, external waits, parked tasks, and handoffs. Also handles an explicit cross-supervisor protocol request.
---

# Todo continuity

Use the flat `~/code/todo/` inventory only when work must survive the current
turn/process and Git plus conversation cannot safely recover its live state.
Ordinary plans, in-turn delegation, and recoverable worktrees need no record.

## Keep a resumable record

- One Markdown file with TOML front matter per independently resumable unit;
  no nested records or `main/`. `AGENTS.md` and `agent-coord.md` are singletons.
- Record the outcome, exact owner, current checkpoint, executable next actions,
  observed verification, and recovery/cleanup conditions. Include only needed
  dependencies, conversation IDs, coordination facts, and every live lane.
- Give independently required resumable execution one `[[attempt]]`.
  Forecast/staffing facts enter only when needed.
- Record a model only from concrete run/dispatch evidence. Unknown identity
  stays an evidence gap, never `self`, `parent`, `default`, or `auto`.
- Replace stale state at meaningful boundaries; do not append a transcript.
- The product owner closes from terminal evidence; the run's host separately
  settles its process, delivery, driver, and child state.
- Delete only after owned changes, dependents, cleanup, continuity, and awaited
  acknowledgements are settled.

For exact fields, resolve `agents path todo-reference` and read its record
schema. Keep repository paths `repo:path` and runtime/worktree paths
`~`-anchored.

## Explicit cross-supervisor request

Read [nixos-config:cross-supervisor transport](references/cross-supervisor.md).
It specifies the paired monitors, duplex helper, event delivery, renewal, and
settlement. Never ask the operator to relay protocol tokens. `OPEN` and
`RECEIVED` convey no work ownership; transfers need separate acknowledgement.
