# The Claude Code nix module — operational notes

The module that wires Claude Code onto the system:
`~/code/nixos-config/modules/claude/default.bnix` (edit the `.bnix`;
`default.nix` is generated). It provides the `claude-code-latest` package,
out-of-store symlinks into `~/code/nixos-config/dotfiles/claude/`
(`commands` / `skills` / `hooks` / `agents` / `CLAUDE.md`, plus the
`~/code/CLAUDE.md` routing file), Orchestration's cached-plugin reconciliation, and MCP
server registration (`fram`, `north`, `linear-mcp-msa-new`). All activation entries are best-effort
(`timeout … || true`) so a network blip never fails a rebuild. (The caveman
plugin install was decommissioned 2026-07-23 — see thread
019f8ee2-22fe-7894-be59-697e56c1b55a; `dotfiles/caveman/config.json` remains
as an untouched Phase 2 archive candidate.)

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
generation activation. Plugin install and Orchestration reconciliation deliberately
run after reseeding so supported plugin state is restored in the same DAG.

If the runtime target ever becomes a `/nix/store/…` symlink, `claude plugin
install` dies with `EROFS: read-only file system`. Plugin-install activation
entries are ordered `entryAfter ["writeBoundary" "seedClaudeSettings"]` so the
writable regular file exists before the plugin CLI touches it.

The statusLine is wired in **settings.json, not plugin.json** — Claude Code
plugins cannot own `statusLine`. It points at
`~/code/nixos-config/dotfiles/claude/statusline.sh`, a self-contained segment
bus in this repo.

## Orchestration plugin — exact-revision managed source + synchronized cache

Claude Code does not run marketplace plugins in place. It copies them to
`~/.claude/plugins/cache`, and local/third-party marketplaces do not auto-update
by default. Merely declaring a Orchestration directory marketplace in
`~/code/nixos-config/dotfiles/claude/settings.json` therefore does not make a
new Claude session consume a newer Orchestration commit.

`syncOrchestrationPlugin` runs after `seedClaudeSettings` on every `firn rebuild`. It
executes `~/code/nixos-config/scripts/claude-orchestration-plugin-sync.sh` from the
evaluated snapshot and receives the exact `inputs.orchestration.rev` that entered the
built closure. The script resolves that object from `~/code/orchestration` and
materializes it at
`~/.local/state/north/orchestration-plugin-source`, the stable directory marketplace
declared in settings. That source is a marker-owned, detached Git worktree at
the exact built revision. It is also Git-locked against prune/removal. Before
creating it, the sync atomically publishes a durable sidecar intent naming the
canonical Orchestration common directory, managed path, and exact selected revision.
If activation dies after `git worktree add` but before the marker is finalized,
the next activation validates that intent plus the clean detached worktree and
completes ownership automatically. After later exact checkouts, it atomically
converges the intent to the new managed HEAD before touching Claude. Crashes on
either side of checkout/intent publication are recoverable on the next run; the
checker requires intent, managed HEAD, cache, and verified input to agree.

The developer's primary `~/code/orchestration` checkout is only the object database:
its active branch, HEAD, dirty bytes, and the current shape of
`refs/heads/main` never select plugin bytes. An unknown existing managed path,
unexpected worktree changes, a foreign worktree/lock, or a missing exact object
fails closed without clobbering anything.

The script first reads Claude's supported marketplace registry. A fresh
profile is registered with `plugin marketplace add`; the one recognized legacy
state—the single `orchestration` directory marketplace at `~/code/orchestration`—is
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

The operating loop stays one command after a Orchestration change lands on local
`refs/heads/main`: `firn rebuild`. Firn verifies and promotes that exact commit
without requiring the primary checkout to switch branches or become clean,
then the activation reconciles Claude's cached copy. The next Claude session
loads it; an already-running session retains the plugin snapshot it started
with until Claude reloads plugins or the session restarts.

Codex and North have no corresponding cache pointer: the shared
`~/code/nixos-config/dotfiles/agents/AGENTS.md` routes Codex to
`~/code/orchestration`, while North reads `~/code/orchestration/staffing/catalog.json`,
provider catalogs, and Orchestration prompt blocks directly.

## caveman plugin — DECOMMISSIONED 2026-07-23

The caveman plugin (fork `tompassarelli/caveman`, marketplace entry, statusline
segment, `installCaveman`/`syncOrchestrationPlugin`-style activation) was unplugged
from this repo's settings.json and statusline per North thread
019f8ee2-22fe-7894-be59-697e56c1b55a — savings were unproven and the fork
carried preservation debt. `dotfiles/caveman/config.json` is left in place,
default off, as a Phase 2 archive candidate; the plugin install/marketplace
wiring in `modules/claude/default.bnix` and the `~/code/caveman` repo itself
are Phase 2 scope, not yet removed. See the thread for the full rationale and
the remaining north-side dial (`north config caveman`, `AGENT_CAVEMAN`).

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
