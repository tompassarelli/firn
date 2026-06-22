# Personal CLAUDE.md (global)

These rules apply to every session, regardless of working directory.

# lodestar

When starting work on anything nontrivial, read
`~/code/lodestar/docs/operating-manual.md` first. It's the operating manual for
plans, time tracking, and session behavior. If anything elsewhere contradicts
it, the manual wins.

Trivial actions — one-shell-command lookups, reading a single file,
quick clarifications — don't need the full manual loaded.

**Threads are claim-native (as of 2026-06-15 — the big cutover).** A thread file
is `@<id>` + `predicate  object` triple lines + `---` + prose body; refs are
`@id`, literals are EDN. There is **no `state` enum** — lifecycle is *derived*
from facts: `committed` (accepted/in-play), `outcome` (done), `abandoned`
(canceled), `driver` (active now), `depends_on` (blocked). A fresh capture is
**`committed`** by default. Relatedness is `relates_to @<thread>` (no string
tags — former tags are `@topic-*` threads). ids are `2026-06-15-150040`.
**There is ONE CLI/engine: `lodestar`** — `los` is **gone entirely**: thread ops
are `lodestar`, and time tracking is **`lodestar clock`** (claim-native sessions
— `session_of`/`start_time`/`end_time` rolling up to a thread for estimate-vs-
actual; Clockify is an on-demand sync projection via `clock sync`). Full spec:
`~/code/lodestar/docs/claim-native-redesign.md`.


## lodestar is claim-backed — write safely under concurrent agents

lodestar threads are backed by the Lodestar claim graph (engine `~/code/fram`;
canonical log `~/.local/state/lodestar/claims.log`). Assume **other agents
may be editing concurrently**:

**Session-start handshake (before coordinating lodestar, mirrors beagle-doctor):**
run `lodestar doctor`. If it reports DOWN/DEGRADED, run
`lodestar up` to start the coordinator on the canonical log.
(Optional heartbeat: `/loop 10m lodestar up` keeps it alive.)

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `lodestar import` to fold edits into the claim
  log (idempotent; safe to run anytime).
- **Do not run `lodestar export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized claim writes go through the coordinator** via `lodestar tell <id>
  <pred> <value>` / `untell <id> <pred> <value>` — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `lodestar
  set`, which appends the log directly and races. For creating whole new threads,
  `lodestar capture "<title>"` (claim-first) or file-edit + `import` is fine
  (distinct files don't collide); for field changes on existing threads under
  concurrency, prefer `tell`.
- Reads are instant off the warm daemon (`lodestar serve`): ready / blocked /
  leverage / validate in ~1ms.


## When editing/advising, you need to resolve the CLAUDE.md files relevant to the work

Let's see the user alludes to something inside

```bash
ls ~/code/<repo>/..
```
Always start by identifying the claude.md at the root, which provides essential context

## Nix dev environments: use direnv, never recommend `nix develop` or `nix shell`

When a project has a Nix dev shell, the user activates it via **direnv**
(`.envrc` with `use flake` and a populated `.direnv/`). `cd <repo>`
auto-activates the shell; no manual command is needed.

Do not tell the user to run `nix develop` / `nix-shell`. If they're in
the project dir, the shell is already active. If `.envrc` is missing,
suggest writing one (`echo 'use flake' > .envrc && direnv allow`)
instead of recommending the bare `nix develop` workflow.

Same rule for `devenv` / `flake.nix devShells` — surface the direnv
trigger, not the underlying command.

## System / global config changes go through `~/code/nixos-config` — ALWAYS

Any change to the machine's configuration **or** to Claude's global setup is made
**idiomatically through `~/code/nixos-config`**, never ad-hoc in the live system.
This covers: Claude global config (`skills/`, `CLAUDE.md`, `commands/`,
`settings.json`), system packages, services, dotfiles, and any host / home-manager
setting. The whole point is **reproducibility** — a fresh rebuild on any machine
must reproduce the change.

- `~/.claude/{skills,CLAUDE.md,commands,settings.json,hooks}` are
  `mkOutOfStoreSymlink`s into `nixos-config/dotfiles/claude/` (see
  `modules/claude/default.nix`). Editing them edits the repo *directly* and is
  live immediately (no rebuild) — **but you MUST commit it to `nixos-config`**,
  or it isn't reproducible. (`hooks/` was nix-wired 2026-06-20; until the next
  rebuild creates the symlink, `settings.json` still reaches them by absolute
  repo path, which also works.)
- **The Claude config is CI-validated** — `.github/workflows/claude-config.yml`
  runs `scripts/claude-config-check.sh`: shellchecks the hooks, JSON-validates
  `settings.json`, and asserts every wired hook path exists + is executable. Run
  `scripts/claude-config-check.sh --local` on the machine to ALSO `command -v`
  the CLIs this file names (so a removed/renamed tool fails loudly instead of
  rotting silently). This is the anti-rot gate; keep it green.
- **Behavior-injecting hooks have an opt-out kill-switch:**
  `CLAUDE_NO_AUTHORING_HOOKS=1` makes the SessionStart beagle handshake and the
  PreToolUse claim-canonical guard no-op — used to pin a neutral, confound-free
  session (e.g. for experiments). Unset = normal behavior.
- For anything NOT already wired (a new package, service, dotfile, or symlink), add
  it to the appropriate nix module (+ `home.file` / `mkOutOfStoreSymlink`), then
  rebuild. Do not drop untracked files into the live system.
- After any such change: `git -C ~/code/nixos-config status` should have no stray
  untracked state, and the change must survive a fresh rebuild. When you make a
  global/system edit, say so and commit it — don't leave it dangling in `~`.

## GitHub releases: version only in title

Use just the version tag as the release title (e.g. `v0.5.0`). No
`—` subtitle or description in the title. Details go in the body.
