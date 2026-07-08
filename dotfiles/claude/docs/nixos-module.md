# The Claude Code nix module — operational notes

The module that wires Claude Code onto the system:
`~/code/nixos-config/modules/claude/default.bnix` (edit the `.bnix`;
`default.nix` is generated). It provides the `claude-code-latest` package,
out-of-store symlinks into `~/code/nixos-config/dotfiles/claude/`
(`commands` / `skills` / `hooks` / `agents` / `CLAUDE.md`, plus the
`~/code/CLAUDE.md` routing file and caveman's `~/.config/caveman/config.json`),
the **caveman** plugin install, and MCP server registration (`fram`, `tern`,
`linear-mcp-msa-new`). All activation entries are best-effort
(`timeout … || true`) so a network blip never fails a rebuild.

Why everything routes through nixos-config (reproducibility rule, CI
validation, hooks kill-switch):
`~/code/nixos-config/dotfiles/claude/docs/nixos-config-rules.md`.

## settings.json is a WRITABLE symlink — load-bearing

`linkClaudeSettings` points `~/.claude/settings.json` **directly** at
`~/code/nixos-config/dotfiles/claude/settings.json`, bypassing the nix store,
so Claude Code can atomic-write it (`settings.json.tmp` + rename). If it ever
reverts to a `/nix/store/…` symlink, `claude plugin install` dies with
`EROFS: read-only file system`. `installCaveman` is ordered
`entryAfter ["writeBoundary" "linkClaudeSettings"]` for exactly this reason —
settings must be writable before the plugin CLI touches it.

Cost of the writable symlink: every `claude plugin install/uninstall/enable`
**reserializes** `~/code/nixos-config/dotfiles/claude/settings.json` (reorders
keys) → a tracked diff. Pure reorder, no content change. Commit it or discard
it; it recurs on the next plugin op. Not worth fighting.

The statusLine is wired in **settings.json, not plugin.json** — Claude Code
plugins cannot own `statusLine`. It points at
`~/code/nixos-config/dotfiles/claude/statusline.sh`, a self-contained segment
bus in this repo; the caveman segment reads the plugin's flag file directly
(no plugin-cache dependency).

## caveman plugin — fork + sha pin

Source is a personal fork: **`tompassarelli/caveman`** (upstream is
`juliusbrussee/caveman`; local clone `~/code/caveman`). The fork's
`.claude-plugin/marketplace.json` pins an exact commit sha. nixos installs via
`claude plugin marketplace add` + `claude plugin install caveman@caveman`
(`@marketplace` form = the caveman plugin from the caveman marketplace).

`WANT` in `default.bnix` is the **first 12 chars** of that sha = the on-disk
cache dir name: `~/.claude/plugins/cache/caveman/caveman/<WANT>`.

### Bumping caveman

1. Edit the fork (`~/code/caveman`), run its tests
   (`node tests/test_caveman_stats.js`), commit.
2. Bump the fork's `.claude-plugin/marketplace.json` sha → that commit; commit;
   push. (Two-commit dance: a code commit, then a pin commit pointing at it.)
3. Set `WANT=<same 12-char sha>` in
   `~/code/nixos-config/modules/claude/default.bnix`.
4. `firn build` → `firn rebuild`. The activation reconciles (uninstall + install).

**Keep the fork pin and `WANT` on the same sha.** If they diverge, `install`
fetches the fork pin, the `WANT` cache dir never appears, and the `elif` branch
re-clones on every rebuild.

### Why the activation looks the way it does (hard-won)

- `claude plugin install` **clones the plugin repo over SSH** (`git@github.com:`).
  A host that authenticates GitHub over HTTPS (no SSH key) gets
  `Permission denied (publickey)`. Worked around with a throwaway
  `GIT_CONFIG_GLOBAL` carrying `url.https://github.com/.insteadOf
  git@github.com:`, scoped to the one command — no global git change.
  (`marketplace add/update` already use HTTPS; only the plugin clone needs it.)
- `claude plugin install` **no-ops when already installed**, and
  `claude plugin update` also needs SSH — so the only reliable upgrade is
  **uninstall + install** after `marketplace update`. That is the `elif` branch.
- Plugin **hooks load at session start only**. After an upgrade, new hooks
  (e.g. the Stop hook that keeps the statusline fresh) do not fire until Claude
  Code is restarted. A rebuild alone is not enough.

### Recovery: half-uninstalled plugin

`claude plugin uninstall` drops the entry from
`~/.claude/plugins/installed_plugins.json` (a writable runtime file, not nix). A
failed reinstall leaves it gone while the cache dir survives. Restore by hand:
re-add the entry `{scope: "user", installPath: …/cache/caveman/caveman/<sha>,
version: <sha>, gitCommitSha: <full sha>}`, then `claude plugin list` should see
it again. `enabledPlugins` in settings.json is tracked separately.

## MCP servers

`registerMcpServers` adds `fram` + `tern` idempotently (guarded on
`mcp get`). `fram` is the **generic** engine — its corpus is selected at
deploy time via env (`FRAM_LOG` / `FRAM_THREADS`); never hardcode life-store
paths into the engine itself. Also registers `linear-mcp-msa-new` (HTTP/OAuth,
per-machine auth; msa-old retired 2026-06-30).

## graph-owned guard — accepted gap (decision)

`graph-owned-guard` deliberately covers only Edit/Write/MultiEdit —
Bash-mediated writes (`sed -i`, `tee`) to canonical files are out of contract;
agents are steered by the `graph-owned-authoring` skill.
