# Agent protocol — driving agents via tern

When work means multiple agents, do NOT default to the host's generic `Agent` /
`Workflow` / ultracode spawning. Tern fronts a real, running, *better*
substrate: persistent agents, observable + steerable + durably coordinated
through the claim graph (raw Agent/Workflow are
ephemeral, unobservable mid-flight, un-steerable).

**Use the tern MCP tools** (`mcp__tern__dispatch`, `mcp__tern__spawn`)
to drive agents, plus the pre-edit gate — not the built-in Agent/Workflow tools.
(Enforced mechanically: `agent-spawn-guard.sh` PreToolUse denies native
Agent/Task/Workflow while the dispatch knob is `tern` — view/flip via `my-config` /
`/my-config`. Reinstated 2026-07-03; the P6 prose-only bet did not hold.)
Quick lookups → bash/grep/read inline. Real work → the protocol below.

## The stack

- **Work queue + coordination** = tern threads + claims on `:7977`
  (`ready`/`next`/`leverage`; claim with `driver @agent`).
- **Spawn**: `mcp__tern__dispatch` (thread-driven) / `mcp__tern__spawn` (ad-hoc)
  — dormant-until-pinged (~0 idle tokens).
- **Footprint**: declare before editing — `~/code/tern/bin/concern declare|overlap|status`
  (`overlap <id>` marks likely-to-land work per line; alias: `shape`).
- **Reach a live agent**: it arms `~/code/tern/bin/tern listen <id>` (alias: `tern-arm`); ping with
  `bb ~/code/tern/cli/msg-cli.clj 7977 send <from> <to> "<subject>" "<msg>"` — a
  message IS the steer. Observe via tern web (`:8088`, when the web client is running).
- **Concurrency is the engine's job** — fram owns write-serialization + OCC + the `lease`
  primitive (`acquire`/`release`/`fence`); apps express coordination as claims, never
  self-rolled locks. (`driver` = app intent; `lease` = DB mutual-exclusion — never conflate.)
- Recursive teams coordinate peer-to-peer — ALWAYS through the protocol, NEVER
  ultracode/Workflow.

Org brain: PLAYBOOK = tern thread `2026-06-22-232740` (consult first; append
learnings via `tern tell 2026-06-22-232740 learning "…"`). How-to:
~/code/tern/docs/operating-manual.md. Per-repo surface: `~/code/tern/CLAUDE.md`.
