# The Claude Code nix module — operational notes

The module that wires Claude Code onto the system:
`nixos-config:modules/claude/default.bnix` (edit the `.bnix`;
`default.nix` is generated). It provides the `claude-code-latest` package,
provider-specific files from `nixos-config:dotfiles/claude/`, composed
`~/.agents` policy and hooks from `north:profiles/tom`, the atomic shared skill
farm at `~/.local/state/north/skills`, the
`~/code/CLAUDE.md` routing file, and MCP server registration (`fram`, `north`,
`linear-mcp-msa-new`, `digitalocean`). All activation entries are best-effort
plugin install was decommissioned 2026-07-23 — see thread
as an untouched Phase 2 archive candidate.)

Why everything routes through nixos-config (reproducibility rule, CI
validation, hooks kill-switch):
`nixos-config:modules/north-profile/firn/docs/nixos-config-rules.md`.

## settings.json is WRITABLE runtime state seeded by the generation

`seedClaudeSettings` materializes the committed
`nixos-config:dotfiles/claude/settings.json` snapshot from the evaluated
generation into `~/.claude/settings.json` as a **regular writable file**. It
atomically replaces missing, legacy-symlink, and existing regular targets on
every activation. That makes future committed settings changes converge while
removing the live dependency on a mutable checkout. Claude still owns a normal
writable file between activations, so `/effort`, plugin enablement, and other
atomic runtime writes continue to work.

The initializer takes an adjacent process lock and stages a complete validated
JSON file before one rename. A crash before rename leaves the old state intact;
the next activation reclaims only its exact stage and retries. There is no
sidecar seed marker or merge: the evaluated generation is authoritative at
activation, then the regular runtime file belongs to Claude until the next
generation activation. Plugin install and Orchestration reconciliation deliberately
run after reseeding so supported plugin state is restored in the same DAG.

If the runtime target ever becomes a `/nix/store/…` symlink, `claude plugin
install` dies with `EROFS: read-only file system`. Plugin-install activation
entries are ordered `entryAfter ["writeBoundary" "seedClaudeSettings"]` so the
writable regular file exists before the plugin CLI touches it.

The statusLine is wired in **settings.json, not plugin.json** — Claude Code
plugins cannot own `statusLine`. It points at
`nixos-config:dotfiles/claude/statusline.sh`, a self-contained segment
bus in this repo.

## Orchestration plugin — directory marketplace inside north

Orchestration lives inside the north repo at `north:orchestration/`
(merged from the retired standalone checkout; the separate flake input is
gone — the code rides the `north` input). Claude Code consumes it as a
directory marketplace declared in
`nixos-config:dotfiles/claude/settings.json`:
`extraKnownMarketplaces.orchestration.source = { source = "directory"; path =
"<north-checkout>/orchestration"; }` with the plugin enabled as
`orchestration@orchestration`. Claude copies marketplace plugins into
`~/.claude/plugins/cache`; a running session keeps the snapshot it started
with until Claude reloads plugins or the session restarts.

The previous machinery — the separate `inputs.orchestration` flake input, the
`syncOrchestrationPlugin` activation step, and
`scripts/claude-orchestration-plugin-sync.sh` materializing a managed
detached worktree at `~/.local/state/north/orchestration-plugin-source` — was
retired with the merge and no longer exists in this repo.

Codex and North have no cache pointer: the composed
`north:profiles/tom/AGENTS.md` routes Codex to
`north:orchestration/`, while North reads
`north:orchestration/staffing/catalog.json`, provider catalogs, and
Orchestration prompt blocks directly.


from this repo's settings.json and statusline per North thread
019f8ee2-22fe-7894-be59-697e56c1b55a — savings were unproven and the fork
default off, as a Phase 2 archive candidate; the plugin install/marketplace
are Phase 2 scope, not yet removed. See the thread for the full rationale and

## MCP servers

`registerMcpServers` adds `fram` + `north` idempotently (guarded on
`mcp get`). `fram` is the **generic** engine — its corpus is selected at
deploy time via env (`FRAM_LOG` / `FRAM_THREADS`); never hardcode life-store
paths into the engine itself. Also registers `linear-mcp-msa-new` (HTTP/OAuth,
per-machine auth; msa-old retired 2026-06-30) and `digitalocean` as a pinned,
scoped stdio server that reads its API token from `~/do-token.txt` at runtime.

## graph-upstream guard — accepted gap (decision)

`graph-upstream-guard` deliberately covers only Edit/Write/MultiEdit —
Bash-mediated writes (`sed -i`, `tee`) to canonical files are out of contract;
agents are steered by the `code-as-facts` skill.
