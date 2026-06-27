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

## Pre-edit gate — MANDATORY before any code change

**Stop before writing code.** Before any Edit/Write/file modification, the
coordinator MUST run this mental gate (one short paragraph, not a doc):

1. **Decompose** — what are the independent subtasks in this change?
2. **Graph** — which subtasks block which? Draw the dependency edges.
3. **Dispatch** — independent subtasks go to lodestar agents IN PARALLEL. Only
   sequentialize what genuinely depends on a prior result.
4. **Coordinate** — the coordinator touches ONLY cross-cutting work that spans
   multiple agents' outputs. If a subtask is self-contained, delegate it.

If there's only ONE subtask (a typo fix, a single-file tweak), skip the gate
and just do it. The gate fires when the change spans 2+ files or 2+ concerns.

**The failure mode this prevents:** grinding through 8 files serially in-context
when 3+ of them were independent and could've run in parallel. The coordinator's
job is coordination, not execution.

## Agent coordination — lodestar protocol, NEVER raw Agent/Workflow

**Hook-enforced.** `agent-redirect.sh` (PreToolUse) intercepts Agent/Workflow and
redirects to lodestar's persistent agent pool. Every session boots as the
**layer-0 coordinator** (`coordinator-session-start.sh`): decompose + delegate,
don't grind solo. Quick lookups → bash/grep/read inline. Real work → lodestar agents.
Kill-switch: `CLAUDE_NO_AUTHORING_HOOKS=1`. Per-session bypass: `/agent-redirect off`.

Full protocol (spawn/role/steer/observe/concurrency):
→ [`docs/agent-protocol.md`](docs/agent-protocol.md)

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
