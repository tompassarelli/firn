# 03 · North — where the substrate plugs into Claude

> HAND-CURATED. How the claim substrate connects to Claude Code. The *runtime*
> facts (which MCP servers are actually live + their commands) are generated in
> `02-local-map.md` — this doc is the conceptual seam.

## What it is (one breath)

- **fram** (`~/code/fram`) = the engine. Every claim is a `(subject predicate
  object)` claim; lifecycle (committed / done / blocked / active) is DERIVED from
  claims, never a stored status.
- **north** = the app on fram: a durable thread / intent ledger, served by a
  coordinator on **:7977** (data → `~/.local/state/north`).

Claude Code is the **client**; north/fram is the **substrate**.

## How it plugs into the harness

Two touch-points (cross-ref the levers in `01-canonical.md`):

1. **MCP servers** — lever ⑥. `fram-mcp` + `north-mcp`, user scope, registered
   in `~/.claude.json` by the `registerMcpServers` activation in `~/code/nixos-config/modules/claude`.
   Their instruction prose loads at session start; tool **schemas are deferred**
   (ToolSearch) → ≈0 context cost until used. This is how Claude reads/writes
   claims: `capture` / `tell` / `show` / `ready` / `next` / `leverage` / ….

2. **SDK dispatch** — `~/code/north/sdk/src/dispatch.ts` reads a thread's claims,
   derives posture (unplanned → plan only, atomic → execute, composite → survey),
   injects the right prompt + tool restrictions, and streams through North's provider adapter via
   `query()` from `@anthropic-ai/claude-agent-sdk`. Thread-level state drives
   agent behavior — no role-based hooks needed.

## The seam (why it's structured this way)

Claude reaches the substrate through **MCP** (data) + **SDK dispatch**
(coordination). Concurrency lives in the engine — fram's `lease` primitive
(`acquire`/`release`/`fence`) — never self-rolled in the app. (`driver` = app
intent; `lease` = DB mutual-exclusion — don't conflate them.)

## Pointers

- Agent playbook: north thread `2026-06-22-232740` (consult before reaching for tools).
- Write-safety + thread model: `~/code/north/CLAUDE.md`.
- CNF purity + north-as-client architecture: north thread `2026-06-23-132319`.
