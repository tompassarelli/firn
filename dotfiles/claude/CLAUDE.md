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

## Measure load — never "freeze the box" (recurring reflex; KILL it)

Before EVER claiming "CPU-gated" / "box busy" / "can't run concurrently" / "keep
the box quiet" / "protect the measurement by waiting" — **MEASURE**: `nproc` +
`cat /proc/loadavg`. On a many-core box at low loadavg you are NOT gated. The
impulse is almost always wrong.

- **LLM-agent / A/B / wall-time work is NETWORK-bound** — spawned agents sit at
  ~0% CPU waiting on the API, so local work barely touches their wall-time. The
  real constraint is **API throughput** (concurrent-request limits), not CPU.
- **Default to PARALLEL.** Fan out background work and keep going; don't idle a
  whole machine to babysit one job.
- **Timing-sensitive trials → ISOLATE + MONITOR, never serialize the machine:**
  pin with `taskset -c`, record loadavg at trial start, discard/rerun any trial
  whose contention crossed a threshold. "Could there be confounds?" is answered
  by measure-and-discard, NOT by refusing to do anything else.

This reflex has recurred MULTIPLE times despite correction. Treat any "I should
keep the box quiet / can't parallelize / wait to protect the timing" thought as a
**bug in my own reasoning**: stop, run the two commands above, and parallelize
unless the measured numbers actually forbid it.

## Agent coordination — lodestar protocol

Work coordination uses lodestar threads. SDK dispatch (`~/code/lodestar/sdk/src/dispatch.ts`)
derives agent posture from thread claims: unplanned → plan only, atomic → execute,
composite → survey subtasks.

Full protocol (spawn/role/steer/observe/concurrency):
→ [`docs/agent-protocol.md`](docs/agent-protocol.md)

## Resolve CLAUDE.md files for the work at hand

Before editing/advising in a repo, identify its root `CLAUDE.md` for essential context.

## Nix dev environments: use direnv, never `nix develop` or `nix shell`

Projects activate via **direnv** (`.envrc` with `use flake`). `cd <repo>` =
shell active. If `.envrc` is missing, suggest writing one
(`echo 'use flake' > .envrc && direnv allow`), not bare `nix develop`.

## Racket / Beagle: one pinned racket, never stale bytecode — MANDATORY
→ [`docs/racket-beagle-bytecode.md`](docs/racket-beagle-bytecode.md)
**Read when:** working in any Beagle/Racket project (`~/code/beagle`, `.rkt` edits, `raco`/`racket` invocations); a fix "doesn't take" or racket dies with `body of .../raco.rkt`; building/testing in a git worktree of a flake project.

## System / global config changes go through nixos-config — ALWAYS

Reproducibility is the point. Editing `~/.claude/*` edits nixos-config directly
(symlinks), but you MUST commit it. Rebuild command: `firn rebuild` (not raw
`nixos-rebuild switch`).

Full rules (symlinks, CI validation, hooks kill-switch, adding new wiring):
→ [`docs/nixos-config-rules.md`](docs/nixos-config-rules.md)

## Pushing to GitHub — push freely; the secret scan is the guard, not a human

Default: **PUSH WITHOUT ASKING.** Do not gate routine pushes on human approval —
across many parallel agents that doesn't scale, and it's why work piles up
unpushed. When a change is at a sensible checkpoint (coherent commit, green
build/tests), push it. The human is not a push bottleneck.

What makes this safe is the **secret scan**, not human eyeballs:
- Push via **`safe-push`** (on PATH), not raw `git push`. It scans the
  to-be-pushed commits with gitleaks, refuses force/destructive pushes, and pushes
  the current branch to its upstream. A clean scan ⇒ safe to publish. The guard
  travels with the command, so it protects even repos that have no commit-time hook.
- Still NEVER chain `git commit && git push` in one command — commit, let the
  commit hook run, then `safe-push`.

STOP and do NOT auto-push only for these (the real "compelling reasons"):
- gitleaks flags a secret / key / credential → FIX the leak; never push it.
  (`safe-push` blocks this automatically.)
- Force-push / history rewrite of already-published commits (`--force`, rebased
  shared history) → deliberate, manual.
- Making a private repo **public**, or pushing clearly-sensitive content to a
  public repo.
- The commits aren't yours to publish (another agent's in-flight WIP).

Everything else: push.

## GitHub releases: version only in title

Use just the version tag as the release title (e.g. `v0.5.0`). Details go in
the body.

## Desktop is intentionally translucent — NEVER flag it

My niri compositor applies per-window opacity on purpose. The wallpaper showing
through terminals/browsers is a DELIBERATE aesthetic, not a bug, not a rendering
artifact, not a CSS problem. Do NOT comment on, diagnose, "explain", or try to
"fix" desktop background transparency / niri opacity / wallpaper bleed-through.
Never bring it up.

When judging UI colors from a screenshot, evaluate the **CSS/config color values
themselves** (and the base16 set they come from) — not how they composite over
the wallpaper on screen. If a color looks off, the fix is the value, never the
compositor.
