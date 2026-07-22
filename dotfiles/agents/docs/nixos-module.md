# The Claude Code nix module — operational notes

The module that wires Claude Code onto the system:
`~/code/nixos-config/modules/claude/default.bnix` (edit the `.bnix`;
`default.nix` is generated). It provides the `claude-code-latest` package,
out-of-store symlinks into `~/code/nixos-config/dotfiles/claude/`
(`commands` / `skills` / `hooks` / `agents` / `CLAUDE.md`, plus the
`~/code/CLAUDE.md` routing file and caveman's `~/.config/caveman/config.json`),
the **caveman** plugin install, Gaffer's cached-plugin reconciliation, and MCP
server registration (`fram`, `north`, `linear-mcp-msa-new`). All activation entries are best-effort
(`timeout … || true`) so a network blip never fails a rebuild.

Why everything routes through nixos-config (reproducibility rule, CI
validation, hooks kill-switch):
`~/code/nixos-config/dotfiles/agents/docs/nixos-config-rules.md`.

## settings.json is WRITABLE runtime state seeded by the generation

`seedClaudeSettings` materializes the committed
`~/code/nixos-config/dotfiles/claude/settings.json` snapshot from the evaluated
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
generation activation. Plugin install and Gaffer reconciliation deliberately
run after reseeding so supported plugin state is restored in the same DAG.

If the runtime target ever becomes a `/nix/store/…` symlink, `claude plugin
install` dies with `EROFS: read-only file system`. `installCaveman` is ordered
`entryAfter ["writeBoundary" "seedClaudeSettings"]` so the writable regular
file exists before the plugin CLI touches it.

The statusLine is wired in **settings.json, not plugin.json** — Claude Code
plugins cannot own `statusLine`. It points at
`~/code/nixos-config/dotfiles/claude/statusline.sh`, a self-contained segment
bus in this repo; the caveman segment reads the plugin's flag file directly
(no plugin-cache dependency).

## Gaffer plugin — exact-revision managed source + synchronized cache

Claude Code does not run marketplace plugins in place. It copies them to
`~/.claude/plugins/cache`, and local/third-party marketplaces do not auto-update
by default. Merely declaring a Gaffer directory marketplace in
`~/code/nixos-config/dotfiles/claude/settings.json` therefore does not make a
new Claude session consume a newer Gaffer commit.

`syncGafferPlugin` runs after `seedClaudeSettings` on every `firn rebuild`. It
executes `~/code/nixos-config/scripts/claude-gaffer-plugin-sync.sh` from the
evaluated snapshot and receives the exact `inputs.gaffer.rev` that entered the
built closure. The script resolves that object from `~/code/gaffer` and
materializes it at
`~/.local/state/north/gaffer-plugin-source`, the stable directory marketplace
declared in settings. That source is a marker-owned, detached Git worktree at
the exact built revision. It is also Git-locked against prune/removal. Before
creating it, the sync atomically publishes a durable sidecar intent naming the
canonical Gaffer common directory, managed path, and exact selected revision.
If activation dies after `git worktree add` but before the marker is finalized,
the next activation validates that intent plus the clean detached worktree and
completes ownership automatically. After later exact checkouts, it atomically
converges the intent to the new managed HEAD before touching Claude. Crashes on
either side of checkout/intent publication are recoverable on the next run; the
checker requires intent, managed HEAD, cache, and verified input to agree.

The developer's primary `~/code/gaffer` checkout is only the object database:
its active branch, HEAD, dirty bytes, and the current shape of
`refs/heads/main` never select plugin bytes. An unknown existing managed path,
unexpected worktree changes, a foreign worktree/lock, or a missing exact object
fails closed without clobbering anything.

The script first reads Claude's supported marketplace registry. A fresh
profile is registered with `plugin marketplace add`; the one recognized legacy
state—the single `gaffer` directory marketplace at `~/code/gaffer`—is
deterministically migrated to the managed source with the same supported
command. Any duplicate or other same-name source fails closed before plugin
mutation. The script then uses Claude's noninteractive `plugin update` command;
on a fresh machine it uses `plugin install`. It never edits
`~/.claude/plugins/installed_plugins.json`, deletes cache directories, or
uninstalls the plugin. Both plugin manifests must omit an explicit version so
Claude reports the Git revision. After an update/install, the script reads
`claude plugin list --json` again and resolves Claude's 12-character (or full)
version back to the exact 40-character built revision.

A bounded process lock serializes the entire worktree + Claude transaction, so
overlapping activations built from different revisions cannot interleave their
checkout, update, and verification steps. Lock wait is capped at 45 seconds;
marketplace/plugin list probes are capped at 10 seconds and marketplace
registration/update/install calls at 30 seconds. Each CLI runs in a supervised
process group: TERM at the deadline, KILL two seconds later, and immediate
whole-group reap after a normal result, so a descendant cannot mutate after the
lock is released. Stdout and stderr each inherit a 256 KiB file-size ceiling.
Activation reports a warning on failure and
`agent-config-check --local` compares the managed worktree and Claude cache
against the exact verified `flake.lock` input revision.

The operating loop stays one command after a Gaffer change lands on local
`refs/heads/main`: `firn rebuild`. Firn verifies and promotes that exact commit
without requiring the primary checkout to switch branches or become clean,
then the activation reconciles Claude's cached copy. The next Claude session
loads it; an already-running session retains the plugin snapshot it started
with until Claude reloads plugins or the session restarts.

Codex and North have no corresponding cache pointer: the shared
`~/code/nixos-config/dotfiles/agents/AGENTS.md` routes Codex to
`~/code/gaffer`, while North reads `~/code/gaffer/staffing/catalog.json`,
provider catalogs, and Gaffer prompt blocks directly.

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

`registerMcpServers` adds `fram` + `north` idempotently (guarded on
`mcp get`). `fram` is the **generic** engine — its corpus is selected at
deploy time via env (`FRAM_LOG` / `FRAM_THREADS`); never hardcode life-store
paths into the engine itself. Also registers `linear-mcp-msa-new` (HTTP/OAuth,
per-machine auth; msa-old retired 2026-06-30).

## graph-upstream guard — accepted gap (decision)

`graph-upstream-guard` deliberately covers only Edit/Write/MultiEdit —
Bash-mediated writes (`sed -i`, `tee`) to canonical files are out of contract;
agents are steered by the `code-as-facts` skill.
