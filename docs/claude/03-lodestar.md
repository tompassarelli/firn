# 03 · Lodestar — where the substrate plugs into Claude

> HAND-CURATED. How the claim substrate connects to Claude Code. The *runtime*
> facts (which MCP servers are actually live + their commands) are generated in
> `02-local-map.md` — this doc is the conceptual seam.

## What it is (one breath)

- **fram** (`~/code/fram`) = the engine. Every fact is a `(subject predicate
  object)` claim; lifecycle (committed / done / blocked / active) is DERIVED from
  claims, never a stored status.
- **lodestar** = the app on fram: a durable thread / intent ledger, served by a
  coordinator on **:7977** (data → `~/.local/state/lodestar`).

Claude Code is the **client**; lodestar/fram is the **substrate**.

## How it plugs into the harness

Three touch-points (cross-ref the levers in `01-canonical.md`):

1. **MCP servers** — lever ⑥. `fram-mcp` + `lodestar-mcp`, user scope, registered
   in `~/.claude.json` by the `registerMcpServers` activation in `~/code/nixos-config/modules/claude`.
   Their instruction prose loads at session start; tool **schemas are deferred**
   (ToolSearch) → ≈0 context cost until used. This is how Claude reads/writes
   claims: `capture` / `tell` / `show` / `ready` / `next` / `leverage` / ….

2. **The fleet protocol** — replaces raw `Agent`/`Workflow`. When work means
   multiple agents, the sanctioned substrate is lodestar threads on **:7977**
   (pick/claim work with `driver @agent`) + the **:7978** coordinator (roles +
   leases), NOT the host's generic spawning. Persistent, role-based, observable,
   steerable.

3. **Redirect hook** — lever ⑬. `fleet-redirect.sh` (`PreToolUse`) intercepts raw
   `Agent`/`Workflow` calls and redirects them to the fleet so habit can't bypass it.
   Kill-switch: `CLAUDE_NO_AUTHORING_HOOKS=1`.

## The seam (why it's structured this way)

Claude reaches the substrate through **MCP** (data) + the **fleet protocol**
(coordination); the **guard hook** keeps the boundary honest. Concurrency lives in
the engine — fram's `lease` primitive (`acquire`/`release`/`fence`) — never
self-rolled in the app. (`driver` = app intent; `lease` = DB mutual-exclusion —
don't conflate them.)

## Pointers

- Fleet playbook: lodestar thread `2026-06-22-232740` (consult before reaching for tools).
- Runbook: `~/code/fleet-data/RUNBOOK.md`.
- Write-safety + thread model: `~/code/lodestar/CLAUDE.md`.
- CNF purity + lodestar-as-client architecture: lodestar thread `2026-06-23-132319`.

## Known gaps (→ next work item)

The integration is **under-leveraged**: the natural reach is still often raw
`Agent`/`Workflow` (blocked by the guard) rather than the lodestar fleet, and the
claim tools aren't pulled in as a default coordination surface. Closing those gaps
— making lodestar the *natural* default rather than the guarded-against fallback —
is the next task. Brainstorm + fixes tracked separately.
