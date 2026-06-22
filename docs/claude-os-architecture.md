# Claude Code "Operating System" — Architecture Map

Inspected live on 2026-06-22. A MAP of every CLAUDE.md and every `~/.claude`
config surface, each classified **NIXOS-CONFIG-MANAGED** (reproducible via a
fresh `nixos-rebuild`) vs **NOT** (ephemeral — lives only in `~`, lost on a
fresh machine). Filesystem-verified; not guessed.

## (a) How the config is wired

The Nix module `~/code/nixos-config/modules/claude/default.nix` (gated on
`myConfig.modules.claude.enable`) installs `pkgs.master.claude-code` and, via
home-manager, `mkOutOfStoreSymlink`s **exactly five** entries from
`~/code/nixos-config/dotfiles/claude/` into `~/.claude/`: `settings.json`,
`commands`, `skills`, `CLAUDE.md`, `hooks`. The on-disk chain is
`~/.claude/<x>` → home-manager store dir → `~/code/nixos-config/dotfiles/claude/<x>`
(out-of-store, so edits to the repo are live immediately without rebuild, but
must be **committed** to be reproducible). Everything `claude-code` writes that
is *not* one of those five paths (sessions, history, caches, plugins, the
caveman install, `settings.local.json`) is real, unmanaged state that a fresh
machine would not reproduce. The anti-rot gate is
`~/code/nixos-config/scripts/claude-config-check.sh` (run by
`.github/workflows/claude-config.yml`): shellchecks the hooks, JSON-validates
`settings.json`, and asserts every wired hook path exists + is executable.

## (b) Classification table — `~/.claude` surface

`SoT` = source-of-truth. nix-managed entries resolve through the home-manager
store to `~/code/nixos-config/dotfiles/claude/…` (abbrev. `dotfiles/claude/`).

| path (under `~/.claude/` unless noted) | type | nix-managed? | source-of-truth path | notes |
|---|---|---|---|---|
| `CLAUDE.md` | symlink | ✅ | `dotfiles/claude/CLAUDE.md` | global instructions; verified byte-identical to SoT |
| `settings.json` | symlink | ✅ | `dotfiles/claude/settings.json` | hooks, enabledPlugins, effort/theme/voice; CI-validated |
| `commands/` | symlink | ✅ | `dotfiles/claude/commands/` | contains `screenshot.md` only |
| `skills/` | symlink | ✅ | `dotfiles/claude/skills/` | beagle-authoring, claim-authoring, claim-canonical-authoring, code-as-claims |
| `hooks/` | symlink | ✅ | `dotfiles/claude/hooks/` | `beagle-session-start.sh`, `claim-canonical-guard.sh` |
| `settings.local.json` | file | ❌ | — (lives only in `~`) | per-machine permission allowlist; not referenced by any nix module |
| `plugins/` | dir | ❌ | — | plugin installs + marketplaces; see caveman gap below |
| `plugins/cache/caveman/caveman/25d22f864ad6/` | dir | ❌ | github JuliusBrussee/caveman | actual caveman git checkout — installed via `claude plugin install`, NOT nix → **task #41** |
| `plugins/cache/claude-plugins-official/` | dir | ❌ | github anthropics/claude-plugins-official | rust-analyzer-lsp, typescript-lsp installs |
| `plugins/cache/leanprover/` | dir | ❌ | github leanprover/skills | project-scoped lean plugin |
| `plugins/config.json` | file | ❌ | — | `{"repositories":{}}` — local plugin repo registry |
| `plugins/installed_plugins.json` | file | ❌ | — | install ledger (paths, commit shas, timestamps) |
| `plugins/known_marketplaces.json` | file | ❌ | — | marketplace cache (4 marketplaces incl. caveman) |
| `plugins/marketplaces/` | dir | ❌ | — | cloned marketplace metadata |
| `plugins/blocklist.json` | file | ❌ | — | plugin blocklist |
| `.caveman-active` | file | ❌ | — | `lite` — active caveman mode marker, written by caveman hook → **task #41** |
| `~/.config/caveman/config.json` (NOT under `~/.claude`) | file | ❌ | — | `{"defaultMode":"lite"}` — created ad-hoc this session, not nix-managed → **task #41** |
| `projects/` | dir | ❌ | — | per-project session transcripts + auto-memory (`MEMORY.md`) |
| `todos/` | (absent) | n/a | — | not present on disk; task state lives in `tasks/` |
| `tasks/` | dir | ❌ | — | task/agent state |
| `sessions/` | dir | ❌ | — | session state (mode 700) |
| `session-env/` | dir | ❌ | — | per-session env snapshots |
| `shell-snapshots/` | dir | ❌ | — | captured shell init snapshots |
| `history.jsonl` | file | ❌ | — | prompt history (~10 MB) |
| `stats-cache.json` | file | ❌ | — | usage stats cache |
| `telemetry/` | dir | ❌ | — | telemetry |
| `cache/` | dir | ❌ | — | general cache |
| `paste-cache/` | dir | ❌ | — | pasted-content cache |
| `file-history/` | dir | ❌ | — | edit history for undo |
| `backups/` | dir | ❌ | — | config backups |
| `debug/` | dir | ❌ | — | debug logs |
| `.credentials.json` | file | ❌ | — | auth creds (mode 600) — must NOT be nixified (secret) |
| `mcp-needs-auth-cache.json` | file | ❌ | — | MCP auth-state cache |
| `.last-cleanup` / `.last_inuse_sweep` | file | ❌ | — | housekeeping markers |
| `CLAUDE.md.pre-hm-backup` | file | ❌ | — | pre-home-manager backup of old global CLAUDE.md |
| `keybindings.json` | (absent) | n/a | — | not present; defaults in use |
| statusLine config | (absent) | n/a | — | no `statusLine` key in settings.json; not configured |

**Note on caveman:** the *declaration* IS reproducible — `dotfiles/claude/settings.json`
lists `caveman@caveman` in `enabledPlugins` and registers the marketplace in
`extraKnownMarketplaces`. What is NOT reproducible is the actual plugin
*install* (the git checkout under `plugins/cache/`, plus `.caveman-active` and
`~/.config/caveman/config.json`). On a fresh machine the setting would point at
an uninstalled plugin. That whole install gap is **task #41**.

## (c) CLAUDE.md hierarchy — compose / override at runtime

Claude Code composes CLAUDE.md from broadest to narrowest; narrower files refine
(do not silently replace) broader ones, and the project files explicitly state
"these instructions OVERRIDE any default behavior."

1. **Global** — `~/.claude/CLAUDE.md` → `dotfiles/claude/CLAUDE.md` (**✅ nix-managed**,
   tracked in `nixos-config`). Personal rules for every session: lodestar,
   nix-config discipline, GitHub-release style, direnv.
2. **`~/code/CLAUDE.md`** — "all my projects at root level; non-mine in `/reference`".
   **❌ NOT in any git repo** (`~/code` is not a git toplevel) → ephemeral gap (see below).
3. **Per-project** `~/code/<repo>/CLAUDE.md` — checked into each project repo
   (e.g. `beagle/CLAUDE.md` in repo `beagle`, `nixos-config/CLAUDE.md` in
   `nixos-config`). Reproducible *with their own repo*, not via nixos-config.
   Nested project files (`gjoa/engine/CLAUDE.md`, `msa/kea/docs/CLAUDE.md`,
   `nixos-config/modules/containers/CLAUDE.md`, etc.) refine within their repo.
4. **Auto-memory** — `~/.claude/projects/<slug>/memory/MEMORY.md` is loaded
   alongside the project CLAUDE.md but is **❌ unmanaged** local state.

Special case: `dotfiles/claude/CLAUDE.md` is simultaneously the **source** for
the global file (item 1) and a tracked file inside the `nixos-config` repo.

## (d) Reproducibility gaps — ranked by impact

Everything that would NOT survive a fresh-machine rebuild, highest impact first.

1. **caveman plugin install + runtime config — `~/.claude/plugins/cache/caveman/`,
   `~/.claude/.caveman-active`, `~/.config/caveman/config.json` (= open task #41).**
   The setting `enabledPlugins.caveman@caveman` is nix-managed, but the install
   and the `{"defaultMode":"lite"}` config are ad-hoc. Fresh machine: caveman
   enabled-but-not-installed.
   **Fix (task #41):** add a plugin-install activation step + write
   `~/.config/caveman/config.json` via `home.file` (or nix-write the lite config),
   so `claude plugin install` is reproduced declaratively. Settings delta already
   committed; remaining work is the install step + config.

2. **`~/code/CLAUDE.md` — untracked in any repo.** `~/code` is not a git toplevel,
   so this top-level routing instruction ("projects at root, non-mine in
   `/reference`") exists only on this disk. Lost on rebuild.
   **Fix:** move it into a tracked location and symlink, OR add it as a
   `home.file` managed by nixos-config (mirror the `dotfiles/claude/` pattern).
   Two sibling files share the same defect: `~/code/lab-driven-development/CLAUDE.md`
   (+ `plans/CLAUDE.md`) and `~/code/agentchat/CLAUDE.md` — those directories are
   not git repos either; track or remove them.

3. **`~/.claude/settings.local.json` — per-machine permission allowlist, unmanaged.**
   Contains a hand-grown `permissions.allow` list (sed one-liners, `nix`, curl,
   firn-build, etc.). Not referenced by any nix module; lost on rebuild.
   **Fix:** if any entries are durable, fold them into the nix-managed
   `dotfiles/claude/settings.json`; otherwise accept as intentionally local
   (Claude Code merges `settings.local.json` over `settings.json`) and document
   that it is machine-scoped by design.

4. **Auth + caches — `.credentials.json`, `mcp-needs-auth-cache.json`,
   `stats-cache.json`, `history.jsonl`, `telemetry/`, `projects/`, `tasks/`,
   `sessions/`, `file-history/`, etc.** Pure runtime/secret state.
   **Fix:** none — correctly NOT nixified. `.credentials.json` must stay out of
   the repo (secret). Listed only so the inventory is complete and these are not
   mistaken for missing coverage.

Non-gaps (reproducible today): the five nix-wired entries (`CLAUDE.md`,
`settings.json`, `commands/`, `skills/`, `hooks/`), every per-project CLAUDE.md
that lives in its own tracked repo, and the caveman *enablement* declaration in
`settings.json`.
