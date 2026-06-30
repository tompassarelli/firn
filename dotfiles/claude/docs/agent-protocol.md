# Agent protocol — driving agents via tern

When work means multiple agents, do NOT default to the host's generic `Agent` /
`Workflow` / ultracode spawning. Tern fronts a real, running, *better*
substrate: persistent, role-based, lease-gated agents that are observable +
steerable + durably coordinated through the claim graph (raw Agent/Workflow are
ephemeral, unobservable mid-flight, un-steerable).

**Use the tern MCP tools** (`mcp__tern__dispatch`, `mcp__tern__spawn`)
to drive agents, plus the pre-edit gate — not the built-in Agent/Workflow tools.
(The old `agent-redirect.sh` PreToolUse hook was removed; coordination is the
tools + the gate now, not a hard intercept.) Quick lookups → bash/grep/read
inline. Real work → the protocol below.

## The stack

- **Work queue** = tern threads on `:7977` (`ready`/`next`/`leverage`; claim with
  `driver @agent`). **Agent coordination** = `:7978` coordinator (presence /
  roles / leases).
- **Spawn**: `~/code/agent-data/spawn-agent.sh <role[,role]>` — lease-gated roles
  (exclusive → a 2nd holder self-aborts), dormant-until-pinged (~0 idle tokens).
- **Assign/steer by ROLE** (not uuid): `msg-cli.clj <port> send <from> <role> "<task>"`;
  a message IS the steer. **Observe/steer** live via tern web (`:8088`).
- **Concurrency is the engine's job** — fram owns write-serialization + OCC + the `lease`
  primitive (`acquire`/`release`/`fence`); apps express coordination as claims, never
  self-rolled locks. (`driver` = app intent; `lease` = DB mutual-exclusion — never conflate.)
- Recursive teams coordinate peer-to-peer — ALWAYS through the protocol, NEVER
  ultracode/Workflow.

Org brain: PLAYBOOK = tern thread `2026-06-22-232740` (consult first; append
learnings via `tern tell 2026-06-22-232740 learning "…"`). How-to:
`~/code/agent-data/RUNBOOK.md`. Per-repo surface: `~/code/tern/CLAUDE.md`.
