# Personal CLAUDE.md (global)

These rules apply to every session, regardless of working directory.

## tern

Read `~/code/tern/docs/operating-manual.md` before nontrivial work. If
anything elsewhere contradicts it, the manual wins. Trivial actions (one-command
lookups, reading a file, quick clarifications) don't need the full manual.

**Session state lives on threads, not markdown dumps.** Substantive work runs
on a tern thread: milestones → `tell <id> progress`, lessons → `learning`,
done → `outcome`. Writing a `SESSION-DUMP-*.md` is a protocol violation — the
next session reads `tern show <id>`, not a file. Agent briefs = thread refs +
the delta, not full-context restatements.

Thread format + concurrent-agent write safety (`tell`/`capture`/`import`/`export`)
+ the full dogfood protocol:
→ ~/code/nixos-config/dotfiles/claude/docs/tern.md

## Pre-edit gate — MANDATORY at task intake

**Run the gate the moment the shape of the work is clear** — at task intake,
not when the first Edit looms (by then the plan is already set). One short
paragraph, not a doc:

1. **Decompose** — what are the independent subtasks in this change?
2. **Graph** — which subtasks block which? Only sequentialize true dependencies.
3. **Dispatch** — independent subtasks → tern agents IN PARALLEL, each with
   model + effort picked per model-selection.md (tier per SUBTASK, never
   inherited from the session).
4. **Coordinate** — the coordinator touches ONLY cross-cutting seams spanning
   multiple agents' outputs. Self-contained subtask ⇒ delegate it.
5. **Verify** — before calling it done: drive the change end-to-end (not just
   typecheck), and spot-check each worker's load-bearing claims yourself — a
   30-second grep beats trusting a "done" report.

Skip when there's ONE subtask (typo, single-file tweak). Fires at 2+ files or
2+ concerns.

**Failure modes prevented:** serially grinding 8 files when 3+ were independent;
shipping a worker's "done" that never actually landed. Coordinate, don't
execute; verify, don't trust.

## Blocked ≠ stopped — find the compliant adjacent move

When a guard, permission classifier, or owning agent blocks an action: never
retry verbatim, never subvert the intent — find the nearest COMPLIANT move that
still advances the goal (can't delete the file → scrub the offending lines;
can't rewrite a shared log → same-length byte-patch, or package it as a script
for the user). Verify a blocker's load-bearing claim yourself before accepting
OR overriding it. At a hard wall (permission system, another agent's live
dependency): stop, hand the user the finish as ONE command, and say exactly
why you stopped. Denial is information about the path, not the goal.

## Agent coordination — tern protocol

Work coordination uses tern threads. SDK dispatch (`~/code/tern/sdk/src/dispatch.ts`)
derives agent posture from thread claims: unplanned → plan only, atomic → execute,
composite → survey subtasks.

Full protocol (spawn/steer/observe/concurrency):
→ ~/code/nixos-config/dotfiles/claude/docs/agent-protocol.md

## Model selection for parallel work — right tier per agent
→ ~/code/nixos-config/dotfiles/claude/docs/model-selection.md
Match the model tier to the task's REASONING DEMAND, not its importance.
Cheap-and-wide (Haiku/Sonnet) for discovery; expensive-and-narrow (Opus) for
judgment. Coordinator stays on Opus; workers economize.
**sonnet = Sonnet 5 at *medium*** — always pin effort on spawn
(`{model: 'sonnet', effort: 'medium'}` in Workflow, or the `sonnet-worker`
agent); harder ⇒ escalate the MODEL (Opus/Fable), never sonnet high/xhigh.
Sonnet is its own Max bucket — spend it to spare Opus; exhausted ⇒ route to Opus.
**Fable = analyst/planner, never the default implementer** — coding stays ≤ Opus.
Escalate a coding task to Fable only on a real blocker (Opus repeatedly failing
the same defect). In a Fable session, PIN implementation spawns to opus/sonnet —
never let build workers inherit fable.
**Read when:** fanning out agents and choosing `model`/`effort` per agent
(Agent tool, Workflow `opts.model`, cavecrew tiers).

## Measure load — never "freeze the box" (recurring reflex; KILL it)

Any "keep the box quiet / CPU-gated / must wait to protect the timing" thought
is a **bug in my own reasoning** — it has recurred despite correction. Stop and
MEASURE: `nproc` + `cat /proc/loadavg`. Many cores + low loadavg = NOT gated;
parallelize.

- **LLM-agent / A/B / wall-time work is NETWORK-bound** — spawned agents idle
  at ~0% CPU on API waits; the constraint is API throughput, not CPU. Default
  to PARALLEL; don't idle a machine to babysit one job.
- **Timing-sensitive trials → ISOLATE + MONITOR, never serialize the machine:**
  pin with `taskset -c`, record loadavg at trial start, discard/rerun contended
  trials. Confounds are answered by measure-and-discard, not by refusing to work.

## Pushing to GitHub — push freely; the secret scan is the guard, not a human

Default: **PUSH WITHOUT ASKING.** Human-gated pushes don't scale across
parallel agents. At a sensible checkpoint (coherent commit, green build/tests),
push. The guard is the **secret scan**, not eyeballs: push via **`safe-push`**
(on PATH), never raw `git push` — it gitleaks-scans the outgoing commits,
refuses force/destructive pushes, and pushes the current branch to upstream.
Still NEVER chain `git commit && git push` — commit, let the hook run, then
`safe-push`.

STOP and do NOT auto-push only for: a flagged secret/key/credential (FIX the
leak; never push it — safe-push blocks this); force-push / rewrite of published
history; making a private repo public or pushing clearly-sensitive content to a
public one; commits that aren't yours to publish (another agent's in-flight WIP).

## Internal notes go in `docs/private/` — never public `docs/`

Internal agent notes, session status, scratch, and handoffs go in `docs/private/`
(gitignored), NEVER in a public `docs/`. The public `docs/` is end-user-facing only.
This applies to EVERY software project. Before writing an internal note in a repo,
ensure the ignore exists: `~/code/tern/bin/ensure-private-docs` (idempotent —
adds `docs/private/` to that repo's `.gitignore`). tern's spawn hook + SDK
harness announce this to every agent automatically; the rule here is the anchor.

## System / global config changes go through nixos-config — ALWAYS

Reproducibility is the point. Editing `~/.claude/*` edits nixos-config directly
(symlinks), but you MUST commit it. Rebuild command: `firn rebuild` — the USER
runs it (never run it yourself to verify; never raw `nixos-rebuild switch`).

Full rules (symlinks, CI validation, hooks kill-switch, adding new wiring):
→ ~/code/nixos-config/dotfiles/claude/docs/nixos-config-rules.md

## Paths — always full and `~`-anchored

Whenever you mention a filesystem path (in chat, docs, comments, generated
output), write it FULL and `~`-anchored: `~/code/nixos-config/dotfiles/claude/settings.json`,
never a bare/relative `dotfiles/claude/...` or `./...`. `~` for `$HOME` is fine —
but keep everything after it complete. The reader must never have to intuit a cwd.
When touching a repo you're not cwd'd into, read its root `CLAUDE.md` first —
the harness only auto-loads the cwd's.

## Nix dev environments: use direnv, never `nix develop` or `nix shell`

Projects activate via **direnv** (`.envrc` with `use flake`). `cd <repo>` =
shell active. If `.envrc` is missing, suggest writing one
(`echo 'use flake' > .envrc && direnv allow`), not bare `nix develop`.

## Racket / Beagle: one pinned racket, never stale bytecode — MANDATORY
→ ~/code/nixos-config/dotfiles/claude/docs/racket-beagle-bytecode.md
**Read when:** working in any Beagle/Racket project (`~/code/beagle`, `.rkt` edits, `raco`/`racket` invocations); a fix "doesn't take" or racket dies with `body of .../raco.rkt`; building/testing in a git worktree of a flake project.

## Code comments — conservative, terse, high-value

Default bearish — comments rot fast and cost tokens. A good comment encodes
INTENTION, a trade-off, or a path NOT taken and why. A bad comment restates
the code. If it doesn't say something the code can't, drop it.

## GitHub releases: version only in title

Use just the version tag as the release title (e.g. `v0.5.0`). Details go in
the body.

## Desktop is intentionally translucent — NEVER flag it

niri applies per-window opacity ON PURPOSE. Wallpaper showing through
terminals/browsers is a deliberate aesthetic — never comment on, diagnose, or
"fix" it. When judging UI colors from a screenshot, evaluate the CSS/config
values (and their base16 set), not how they composite over the wallpaper; if a
color is off, the fix is the value, never the compositor.
