# The Claude Code nix module — operational notes

The module that wires Claude Code onto the system:
`nixos-config:modules/claude/default.bnix` (edit the `.bnix`;
`default.nix` is generated). It provides the `claude-code-latest` package,
provider-specific files from `nixos-config:dotfiles/claude/`, composed
instructions from the `agents` switchboard, shared `~/.agents` docs and hooks
from `north:profiles/tom`, the atomic shared skill farm at
`~/.local/state/north/skills`, the
`~/code/CLAUDE.md` routing file, and MCP server registration (`fram`, `north`,
`linear-mcp-msa-new`, `digitalocean`).

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
generation activation.

If the runtime target ever becomes a `/nix/store/…` symlink, `claude plugin
install` dies with `EROFS: read-only file system`. Plugin-install activation
entries are ordered `entryAfter ["writeBoundary" "seedClaudeSettings"]` so the
writable regular file exists before the plugin CLI touches it.

The statusLine is wired in **settings.json, not plugin.json** — Claude Code
plugins cannot own `statusLine`. It points at
`nixos-config:dotfiles/claude/statusline.sh`, a self-contained segment
bus in this repo.

## Orchestration and coordination — switchboard sets

The retired Claude plugin and local-directory marketplace are not active
consumer surfaces. The `agents`
switchboard composes `orchestration` from
`nixos-config:dotfiles/agents/modules.d/orchestration.json`, with `staffing`
and the nested `coordination` set as members. Claude, Codex, Hermes, and managed
North workers all resolve the resulting `~/.config/agents/AGENTS.md` or
`CLAUDE.md`; North still reads `north:orchestration/staffing/catalog.json`,
provider catalogs, and prompt blocks directly for managed dispatch.

## MCP servers

`registerMcpServers` adds `fram` + `north` idempotently (guarded on
`mcp get`). `fram` is the **generic** engine — its corpus is selected at
deploy time via env (`FRAM_LOG` / `FRAM_THREADS`); never hardcode life-store
paths into the engine itself. Also registers `linear-mcp-msa-new` (HTTP/OAuth,
per-machine auth; msa-old retired 2026-06-30) and `digitalocean` as a pinned,
scoped stdio server that reads its API token from `~/do-token.txt` at runtime.
