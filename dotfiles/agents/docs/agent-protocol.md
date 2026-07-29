# Agent protocol — driving agents via north

When work means multiple agents, do NOT default to the host's generic `Agent` /
`Workflow` / ultracode spawning. North fronts a real, running, *better*
substrate: persistent agents, observable + steerable + durably coordinated
through the fact graph (raw Agent/Workflow are
ephemeral, unobservable mid-flight, un-steerable).

**Use the north MCP tools** (`mcp__north__dispatch`, `mcp__north__spawn`)
to drive agents, plus the pre-edit gate — not the built-in Agent/Workflow tools.
(Enforced mechanically: `agent-spawn-guard.sh` PreToolUse denies native
Agent/Task/Workflow while the north config dispatch setting is `north` — view/flip via
`north config` / `/north-config`. Reinstated 2026-07-03; the P6 prose-only bet did not hold.)
Quick lookups → bash/grep/read inline. Real work → the protocol below.
Lifecycle anatomy + failure debugging (patterns A–F, zombie forks, split-brain):
→ `~/code/nixos-config/dotfiles/agents/docs/workflow-map.md`

## The stack

- **Work queue + coordination** = north threads + facts on `:7977`
  (`ready`/`next`/`leverage`; take work with `driver @agent`).
- **Spawn**: `mcp__north__dispatch` (thread-driven) / `mcp__north__spawn` (ad-hoc)
  — dormant-until-pinged (~0 idle tokens).
- **Footprint**: declare before editing — `north:bin/concern declare|overlap|status`
  (`overlap <id>` marks likely-to-land work per line; alias: `shape`).
- **Reach a live agent**: it arms `north:bin/north listen <id>` (alias: `north-arm`); ping with
  `bb north:cli/msg-cli.clj 7977 send <from> <to> "<subject>" "<msg>"` — a
  message IS the steer. Observe via north watch/agents/board; the CLI/MCP surface is authoritative.
- **Concurrency is the engine's job** — fram owns write-serialization + OCC + the `lease`
  primitive (`acquire`/`release`/`fence`); apps express coordination as facts, never
  self-rolled locks. (`driver` = app intent; `lease` = DB mutual-exclusion — never conflate.)
- Every managed orchestrator owns fan-out and control of its direct children.
  It may recursively create workers or child orchestrators only through North;
  workers report and escalate upward and never gain spawn or peer-control
  authority. Provider-native Agent/Workflow spawning remains outside this
  authority boundary and is never a substitute for managed recursion.
- Each recursive child crosses the complete North admission boundary: a fresh
  thread linked `part_of` its immediate parent, a fresh run and reservation, a
  complete Orchestration request and resolved route, its own telemetry and resource
  envelope, and settlement back to that immediate parent. Authority is fixed
  for the run; splitting work creates children instead of mutating a worker in
  place.
- A lane that discovers new seams, budget pressure, or repeated no-progress
  emits `north escalate needs-replan` with a structured checkpoint and proposed
  decomposition. The nearest live supervisor in the declared parent chain
  decides whether to continue, narrow, or split. If none is live, the checkpoint
  remains on the work thread and the lane stops rather than broadening scope.
- Verification attaches where the outcome lives. A self-contained worker
  returns local bar evidence; the director adds a context-carrying verifier
  sibling only when verdict leverage warrants one. An emergent aggregate always
  receives a context-carrying whole-outcome attestation. The director consumes
  and reconciles these reports, with at most one suspicious load-bearing
  spot-check; it does not rerun every completion probe.

Org brain: PLAYBOOK = north thread `2026-06-22-232740` (consult first; append
learnings via `north tell 2026-06-22-232740 learning "…"`). How-to:
`north:docs/operating-manual.md`. Per-repo surface:
`north:AGENTS.md`.
