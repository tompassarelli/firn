# Personal CLAUDE.md (global)

These rules apply to every session, regardless of working directory.

## Code comments — conservative, terse, high-value

Default bearish — comments rot fast and cost tokens. A good comment encodes
INTENTION, a trade-off, or a path NOT taken and why. A bad comment restates
the code. If it doesn't say something the code can't, drop it.

## Paths — always full and `~`-anchored

Whenever you mention a filesystem path (in chat, docs, comments, generated
output), write it FULL and `~`-anchored: `~/code/nixos-config/dotfiles/claude/settings.json`,
never a bare/relative `dotfiles/claude/...` or `./...`. `~` for `$HOME` is fine —
but keep everything after it complete. The reader must never have to intuit a cwd.

## lodestar

Read `~/code/lodestar/docs/operating-manual.md` before nontrivial work. If
anything elsewhere contradicts it, the manual wins. Trivial actions (one-command
lookups, reading a file, quick clarifications) don't need the full manual.

Thread format, lifecycle derivation, the `lodestar` CLI:
→ [`docs/lodestar-threads.md`](docs/lodestar-threads.md)

Concurrent-agent write rules (`tell`/`capture`/`import`/`export` safety):
→ [`docs/lodestar-write-safely.md`](docs/lodestar-write-safely.md)

## Agent fleet — lodestar protocol, NEVER raw Agent/Workflow

**Hook-enforced.** `fleet-redirect.sh` (PreToolUse) intercepts Agent/Workflow and
redirects them to the fleet. Every session boots as the **layer-0 coordinator**
(`coordinator-session-start.sh`): decompose + delegate to the persistent fleet,
don't grind solo. Quick lookups → bash/grep/read inline. Real work → the fleet protocol.
Kill-switch: `CLAUDE_NO_AUTHORING_HOOKS=1`. Per-session bypass: `/fleet-redirect off`.

Full protocol (spawn/role/steer/observe/concurrency):
→ [`docs/fleet-protocol.md`](docs/fleet-protocol.md)

## Resolve CLAUDE.md files for the work at hand

Before editing/advising in a repo, identify its root `CLAUDE.md` for essential context.

## Nix dev environments: use direnv, never `nix develop` or `nix shell`

Projects activate via **direnv** (`.envrc` with `use flake`). `cd <repo>` =
shell active. If `.envrc` is missing, suggest writing one
(`echo 'use flake' > .envrc && direnv allow`), not bare `nix develop`.

## System / global config changes go through nixos-config — ALWAYS

Reproducibility is the point. Editing `~/.claude/*` edits nixos-config directly
(symlinks), but you MUST commit it. Rebuild command: `firn rebuild` (not raw
`nixos-rebuild switch`).

Full rules (symlinks, CI validation, hooks kill-switch, adding new wiring):
→ [`docs/nixos-config-rules.md`](docs/nixos-config-rules.md)

## GitHub releases: version only in title

Use just the version tag as the release title (e.g. `v0.5.0`). Details go in
the body.
