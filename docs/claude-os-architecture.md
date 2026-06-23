# Claude Code "Operating System" — Architecture Map

Inspected live on 2026-06-22 (revised 2026-06-23 — MCP servers + closed gaps in
**§(h)**, which supersedes stale claims below where they conflict). A MAP of every
CLAUDE.md and every `~/.claude` config surface, each classified
**NIXOS-CONFIG-MANAGED** (reproducible via a fresh `nixos-rebuild`) vs **NOT**
(ephemeral — lives only in `~`, lost on a fresh machine). Filesystem-verified;
not guessed.

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
`settings.json`, asserts every wired hook path exists + is executable, and (as of
2026-06-23) enforces `autoMemoryEnabled === false` plus, under `--local`, the
home-manager symlink chain and the MCP registration (§(h)).

## (b) Classification table — `~/.claude` surface

`SoT` = source-of-truth. nix-managed entries resolve through the home-manager
store to `~/code/nixos-config/dotfiles/claude/…` (abbrev. `dotfiles/claude/`).

| path (under `~/.claude/` unless noted) | type | nix-managed? | source-of-truth path | notes |
|---|---|---|---|---|
| `CLAUDE.md` | symlink | ✅ | `dotfiles/claude/CLAUDE.md` | global instructions; verified byte-identical to SoT |
| `settings.json` | symlink | ✅ | `dotfiles/claude/settings.json` | hooks, enabledPlugins, effort/theme/voice; CI-validated |
| `commands/` | symlink | ✅ | `dotfiles/claude/commands/` | contains `screenshot.md` only |
| `skills/` | symlink | ✅ | `dotfiles/claude/skills/` | beagle-authoring, claim-authoring, claim-canonical-authoring, code-as-claims |
| `hooks/` | symlink | ✅ | `dotfiles/claude/hooks/` | `beagle-session-start.sh`, `claim-canonical-guard.sh`, `fleet-protocol-guard.sh` |
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

---

# Runtime view — what actually reaches the model's context

Added 2026-06-23. Sections (a)–(d) above map config **provenance** (nix-managed
vs ephemeral). This half maps the **context-assembly pipeline**: the non-speech
material that flows into the token window each session/turn, in load order, and
the exact knob that controls each. Verified against the live session config
(`settings.json` hooks/plugins, `skills/`, the deferred-tool registry, the
SessionStart/UserPromptSubmit hook injections observed in-session).

## (e) Context-assembly pipeline (load order)

```
  ┌─ ONCE PER SESSION ────────────────────────────────────────────────────────┐
  │  ① BASE SYSTEM PROMPT     baked in binary    ✗ CLI can't edit; ✓ SDK replace,
  │                                                ✓ `claude -p --append-system-prompt`
  │  ② TOOL DEFINITIONS       built-in + DEFERRED ✓ permissions.deny ["Bash"] removes;
  │                           (lazy via ToolSearch) deferred MCP/Cron/Web ≈ free until fetched
  │  ③ ENVIRONMENT BLOCK      cwd/git/OS/model/date  ✓ --exclude-dynamic-…-sections
  │  ④ CLAUDE.md HIERARCHY    managed → ~/.claude → ~/code → <repo> → <subdir>
  │                                                ✓ edit the files (broad→narrow refine)
  │  ⑤ AUTO-MEMORY            ~/.claude/projects/<slug>/memory/MEMORY.md + recalled facts
  │  ⑥ MCP INSTRUCTIONS       better-auth/fram/lodestar prose + tool NAMES (schemas deferred)
  │  ⑦ SKILL DESCRIPTIONS     name+description only; BODY deferred until Skill() invoked
  │  ⑧ AGENT TYPES            subagent roster (caveman:*, Explore, Plan, …)
  │  ⑨ SLASH COMMANDS         commands/*.md  (live: screenshot.md)
  │  ⑩ SessionStart HOOK OUT  ← injected as system msg  (beagle-session-start.sh + caveman banner)
  └────────────────────────────────────────────────────────────────────────────┘
  ┌─ EVERY TURN ──────────────────────────────────────────────────────────────┐
  │  ⑪ USER PROMPT
  │  ⑫ UserPromptSubmit HOOK  ← inject text / block prompt (caveman re-injects each turn)
  │  ⑬ TOOL CALLS → results   PreToolUse: block / rewrite input / auto-allow
  │                           PostToolUse: rewrite output / inject context
  │                           (live: claim-canonical-guard.sh on Edit|Write|MultiEdit)
  │  ⑭ COMPACTION             old tool output → summary    ✓ PreCompact hook; autoCompact toggle
  └────────────────────────────────────────────────────────────────────────────┘
```

Key property: injected banners (caveman, beagle handshake) are **hook output**
(⑩/⑫), not model identity. Hooks are the surface to alter bias/inject context
without touching the binary.

## (f) Control surfaces — every knob

| # | Source | Live location | Control / debloat |
|---|---|---|---|
| ① | base system prompt | binary | CLI: append-only (`-p --append-system-prompt`); full replace = SDK / output-style |
| ② | built-in tools | binary | `permissions.deny:["Bash"]` (bare name) removes from context; SDK `disallowedTools` |
| ② | deferred/MCP tools | ToolSearch registry | lazy — near-zero until fetched; remove server = gone |
| ③ | env block | generated | `--exclude-dynamic-system-prompt-sections` |
| ④ | CLAUDE.md | `dotfiles/claude/CLAUDE.md` (nix) + `~/code/CLAUDE.md` (⚠ untracked, gap (d)#2) + per-repo | edit files; primary bias lever |
| ⑤ | auto-memory | `~/.claude/projects/*/memory/` | edit/delete `.md`; `autoMemoryEnabled` |
| ⑥ | MCP | `.mcp.json` / `~/.claude.json` | remove server (instruction block loads eagerly; tools deferred) |
| ⑦ | skills | `~/.claude/skills/` (nix) + plugins | delete dir / disable plugin; `disable-model-invocation` frontmatter |
| ⑧ | agents | agent dirs + plugins | delete files / disable plugin |
| ⑩⑫⑬ | hooks | `settings.json hooks` → `dotfiles/claude/hooks/` | add/remove scripts; `disableAllHooks:true`; kill-switch `CLAUDE_NO_AUTHORING_HOOKS=1` |
| — | plugins | `enabledPlugins` | flip `false` → drops that plugin's skills+agents+hooks+statusline |
| — | model/effort | `settings.json` `model`,`effortLevel` | `/model`, `/config` |

### Tool interception — the three swap paths

A built-in tool's implementation is baked (CLI can't replace `Read`/`Bash`
directly). Three ways to swap behavior:

1. **Hook rewrite** — `PreToolUse` rewrites input args before exec; `PostToolUse`
   rewrites the output the model sees (`updatedToolOutput`). Intercept-and-fake
   is possible. (This repo already does the block half: `claim-canonical-guard.sh`.)
2. **Shadow via MCP** — add `mcp__myfs__read`, `deny` built-in `Read`; model
   routes through your impl.
3. **SDK in-process tools** — define the tool as a TS/Python function. True
   implementation swap.

Hook events (mid-2026, CLI-confirmed): `SessionStart`, `SessionEnd`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`,
`PreCompact`, `Notification`.

## (g) CLI vs Agent SDK vs raw API — and billing

Same engine underneath CLI and the Agent SDK; the SDK is Claude Code as a
library. Escalate only at a specific ceiling.

| Want | CLI | SDK | API |
|---|---|---|---|
| strip context / remove tools / inject bias | ✅ perms+hooks+CLAUDE.md | ✅ | build it |
| intercept & rewrite tool calls | ✅ Pre/PostToolUse | ✅ callbacks | n/a |
| **replace base system prompt** | ✗ (append only) | ✅ | ✅ you own it |
| custom tool as real code | ~ via MCP | ✅ in-proc fn | ✅ |
| **programmatic per-call permission logic** | ✗ static rules | ✅ `canUseTool` | n/a |
| unattended / CI / service | awkward | ✅ | ✅ |

**Billing.** CLI here auths via OAuth subscription (`~/.claude/.credentials.json`)
→ counts against Pro/Max, not API credits. The Agent SDK run locally inherits
that same CLI auth, so it *can* run on the subscription — but Anthropic's
official stance is OAuth tokens are for the CLI + claude.ai; programmatic SDK use
is a gray/disallowed zone for production, where the sanctioned path is
`ANTHROPIC_API_KEY` (pay-per-token). Raw API is credits only. (Billing specifics
move; confirm at docs.claude.com before building production on subscription auth.)

**Verdict.** Stay on CLI for interactive work — debloat/bias-shift is fully
covered by what this repo already manages (CLAUDE.md, hooks, permissions, plugin
toggles). Reach for the SDK only at the three ✗ ceilings: replacing the base
system prompt, real-code custom tools, or programmatic permission logic. Raw API
only if dropping the agent loop entirely (you don't — the SDK gives it for free).

---

## (h) MCP servers + closed gaps (2026-06-23 revision)

Added 2026-06-23. **Supersedes stale claims above where they conflict.**

### MCP servers — `fram` + `lodestar` (linear removed)

Two stdio MCP servers, USER scope, registered in `~/.claude.json`:

| server | command | corpus it reads | role |
|---|---|---|---|
| `lodestar` | `~/code/lodestar/bin/lodestar-mcp` | live store (`~/.local/state/lodestar/`, via the engine's own XDG default) | curated life verbs (ready/next/plate/tell/capture/…) |
| `fram` | `~/code/fram/bin/fram-mcp` | live store — **only because `FRAM_LOG`/`FRAM_THREADS` env point it there** | generic claim engine: raw triple tools + Datalog `query` escape hatch |

Note: `~/.local/state/lodestar` → symlink → `~/code/lodestar-data` (a git repo).
One physical store; engine reads the XDG path, bytes are version-controlled.

**The corpus footgun (fixed 2026-06-23).** `fram` is the *generic* engine; with
no env it defaults to its **repo demo corpus** (`~/code/fram/claims.log`), so an
unconfigured fram MCP silently serves example data, blind to the real board. The
fix selects the corpus at **deployment** (env on the registration) — never by
hardcoding life paths into the engine. `lodestar` avoids the trap because its
wrapper sets the XDG default itself.

**Reproducible registration.** `modules/claude/default.bnix` now ships
`home.activation.registerMcpServers`: a best-effort, idempotent activation that
(re)registers `fram` with the live-corpus env and ensures `lodestar` is present,
so a fresh `firn rebuild` wires both instead of relying on loose `claude mcp add`
state. **Set-once (activation) + verify-always (gate, below).**

**`linear` removed** (2026-06-23) — was registered but unauthenticated/unused, in
both user scope and the nixos-config project-local scope. Other project-scoped
servers (`better-auth` in `~`, `clerk` in `msa/kea`, `gdai` in `godot-test`) are
intentional per-repo and left in place.

**Token note.** fram's tool catalog is GENERATED from the claim vocabulary — one
tool per predicate (`set-/add-/-of/-from`), hundreds on a live corpus. Free here
under MCP **tool-search / deferred loading** (a schema is fetched only when used)
but would blow the context budget in any client without it — a hard portability
constraint when fram is packaged.

### Gate now covers MCP + symlink + memory invariants

`scripts/claude-config-check.sh` (extended 2026-06-23) adds, beyond shellcheck +
JSON + wired-hook checks: `autoMemoryEnabled === false` (reproducibility
invariant, repo content); and under `--local` — every nix-managed `~/.claude/<x>`
resolves to the dotfile SoT (catches a stale/broken home-manager generation), the
USER-scope MCP set is exactly `{fram,lodestar}`, and `fram` targets the live store
not the demo. Project-scoped servers are reported, not failed.

### Earlier gaps now closed

- **gap (d)#2 — `~/code/CLAUDE.md` untracked:** CLOSED. The module manages
  `home.file."code/CLAUDE.md"` → `dotfiles/code/CLAUDE.md` (mkOutOfStoreSymlink).
- **task #41 — caveman install:** CLOSED. `home.activation.installCaveman`
  reproduces the marketplace-add + install (best-effort, timeout-bounded);
  `~/.config/caveman/config.json` is nix-written `{"defaultMode":"full"}`; and the
  plugin is now **version-pinned via a fork** (2026-06-23). caveman's plugin source
  ships as `"./"` (relative → unpinnable) and a *marketplace* source can't carry a
  sha, so the native sha-pin requires owning `marketplace.json`: forked
  `JuliusBrussee/caveman` → `tompassarelli/caveman` (`~/code/caveman`), set the
  plugin `source` to `github {repo, sha=25d22f864ad6}` (fork commit `cf0c679`),
  repointed `settings.json` + the activation at the fork. Gate check `5b` asserts
  the marketplace stays on the fork. Bytes are now exact-pinned, patchable, and
  insulated from upstream `main`.
- The mkOutOfStoreSymlink set is now **six** entries (`settings.json`, `commands`,
  `skills`, `CLAUDE.md`, `hooks`, `code/CLAUDE.md`) plus one nix-written file
  (`.config/caveman/config.json`) — not the "exactly five" stated in §(a).
