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
- **Footprint**: declare before editing — `~/code/north/bin/concern declare|overlap|status`
  (`overlap <id>` marks likely-to-land work per line; alias: `shape`).
- **Reach a live agent**: it arms `~/code/north/bin/north listen <id>` (alias: `north-arm`); ping with
  `bb ~/code/north/cli/msg-cli.clj 7977 send <from> <to> "<subject>" "<msg>"` — a
  message IS the steer. Observe via north web (`:8088`, when the web client is running).
- **Concurrency is the engine's job** — fram owns write-serialization + OCC + the `lease`
  primitive (`acquire`/`release`/`fence`); apps express coordination as facts, never
  self-rolled locks. (`driver` = app intent; `lease` = DB mutual-exclusion — never conflate.)
- Recursive teams coordinate peer-to-peer — ALWAYS through the protocol, NEVER
  ultracode/Workflow.

Org brain: PLAYBOOK = north thread `2026-06-22-232740` (consult first; append
learnings via `north tell 2026-06-22-232740 learning "…"`). How-to:
~/code/north/docs/operating-manual.md. Per-repo surface: `~/code/north/CLAUDE.md`.
