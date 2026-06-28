# ~/code/nixos-config/modules/claude — operational notes

NixOS module for Claude Code: the package, out-of-store symlinks
(commands / skills / hooks / CLAUDE.md), the **caveman** plugin install, and
MCP server registration (`fram`, `lodestar`). All activation entries are
best-effort (`timeout … || true`) so a network blip never fails a rebuild.

## settings.json is a WRITABLE symlink — load-bearing

`linkClaudeSettings` points `~/.claude/settings.json` **directly** at
`~/code/nixos-config/dotfiles/claude/settings.json`, bypassing the nix store, so Claude Code can
atomic-write it (`settings.json.tmp` + rename). If it ever reverts to a
`/nix/store/…` symlink, `claude plugin install` dies with `EROFS:
read-only file system`. `installCaveman` is ordered
`entryAfter ["writeBoundary" "linkClaudeSettings"]` for exactly this reason —
settings must be writable before the plugin CLI touches it.

Cost of the writable symlink: every `claude plugin install/uninstall/enable`
**reserializes** `~/code/nixos-config/dotfiles/claude/settings.json` (reorders keys) → a tracked
diff. Pure reorder, no content change. Commit it or discard it; it recurs on
the next plugin op. Not worth fighting.

The statusLine badge is wired in **settings.json, not plugin.json** — Claude
Code plugins cannot own `statusLine`. The command globs the newest cache dir
(`ls -dt …/cache/caveman/caveman/*/…/caveman-statusline.sh | head -1`), so
stale old cache dirs are harmless.

## caveman plugin — fork + sha pin
→ [`docs/caveman-plugin.md`](docs/caveman-plugin.md)
Personal fork `tompassarelli/caveman`, sha-pinned; `WANT` in `default.bnix` = first 12 chars of that sha = on-disk cache dir name.
**Read when:** bumping caveman (keep fork pin + `WANT` in sync), editing `default.bnix` activation / `installCaveman`, or debugging plugin install (SSH/`EROFS` errors, `claude plugin install/update/uninstall`, half-uninstalled recovery).

## MCP servers

`registerMcpServers` adds `fram` + `lodestar` idempotently (guarded on
`mcp get`). `fram` is the **generic** engine — its corpus is selected at
deploy time via env (`FRAM_LOG` / `FRAM_THREADS`); never hardcode life-store
paths into the engine itself.
