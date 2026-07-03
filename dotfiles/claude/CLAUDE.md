# Personal CLAUDE.md (global)

These rules apply to every session, regardless of working directory.

## tern

Read `~/code/tern/docs/operating-manual.md` before nontrivial work; if anything
elsewhere contradicts it, the manual wins (trivial one-command lookups exempt).
**Session state lives on threads, not markdown dumps** — milestones → `tell <id>
progress`, lessons → `learning`, done → `outcome`. A `SESSION-DUMP-*.md` is a
protocol violation; the next session reads `tern show <id>`, not a file. Agent
briefs = thread refs + the delta.

Thread format + concurrent-agent write safety + full dogfood protocol:
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

Skip when there's ONE subtask (typo, single-file tweak); fires at 2+ files or
2+ concerns. Failure modes this kills: serially grinding files that were
independent; shipping a worker's "done" that never landed. Coordinate, don't
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
Tier = the task's REASONING DEMAND, never its importance. Triage by SHAPE:
execute / implement / integrate / design / invent (doc maps shapes → tiers);
blast radius routes up, importance alone never. The stack:
**sonnet-low** discovers/triages → **sonnet-medium** builds → **opus** judges →
**fable** plans/analyzes the hardest; coordinator stays Opus/Fable. Haiku is
OFF the default stack (2026-07: tool-loop bug, no effort dial, 2 gens stale) —
single-shot bulk classify/extract only, NEVER tool chains. Two hard laws:
**pin BOTH dials on every spawn** (harder ⇒ escalate the MODEL, never sonnet
high/xhigh), and **Fable = analyst/planner, never the default implementer**
(coding ≤ Opus; in a Fable session PIN implementation spawns to opus/sonnet).
Bucket policy, effort ladder, spawn-surface mappings: the doc.
**Read when:** fanning out agents and choosing `model`/`effort` per agent
(Agent tool, Workflow `opts.model`, tern spawn, cavecrew tiers).

## Measure load — never "freeze the box" (recurring reflex; KILL it)
→ ~/code/nixos-config/dotfiles/claude/docs/measure-load.md
Any "keep the box quiet / must wait to protect the timing" thought is a bug in
my own reasoning — MEASURE (`nproc` + `cat /proc/loadavg`) instead of
serializing. LLM-agent work is NETWORK-bound (agents idle ~0% CPU on API
waits): default PARALLEL. The reflex also fires at DESIGN time: never write
"sequential runs / quiet machine" into an experiment protocol unmeasured —
default is max safe parallelism + taskset isolation + loadavg-recorded +
discard rule; A/B arms run SIMULTANEOUSLY (identical conditions = fairer).
**Read when:** tempted to serialize/defer work "to protect the machine",
running timing-sensitive trials/benchmarks, or WRITING an experiment
protocol/pre-registration (isolation protocol in the doc).

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

## Using others' code — check the license first

Before leveraging external code (reference repos in `~/code/reference`, forks,
vendored snippets, "how did X do it" reads): read its LICENSE. Permissive
(MIT/Apache-2.0/BSD/ISC) → adapt freely; carry attribution/NOTICE where the
license requires it. Copyleft (GPL/AGPL/SSPL) → READING for ideas is fine;
FLAG before deriving/copying code into a differently-licensed project.
No license file / "all rights reserved" / non-commercial or no-derivative
terms → flag to the user BEFORE using it as a reference at all. Studying a
mechanism and reimplementing from understanding is always fine — the license
governs copied expression, not ideas. If a license is overly restrictive for
the intended use, say so up front, before any work builds on it.

## Reference reads — vetted takeaways from ~/code/reference
→ ~/code/nixos-config/dotfiles/claude/docs/reference-reads.md
Curated pointers from scanned forks (licenses checked): skill-authoring
methodology, debugging technique docs, measured MCP output caps, benchmark
harness designs. **Read when:** authoring a new skill, building an MCP tool
that returns big payloads, hunting a test-state polluter, or designing an
agent-behavior benchmark.

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

## New code — the ladder is for glue, never the core

Before writing code, ask which layer it lives in. **Incidental code** (glue,
scripts, plumbing, one-off tooling, run-of-the-mill features): walk the ladder —
needs to exist at all? → repo already does it → stdlib → platform native →
existing dep → one-liner → smallest block that works; stop at the first
sufficient rung. The cheapest line is the one never written. **Core code**
(the thing the project IS: compiler internals, novel infra, perf-critical
paths): the ladder INVERTS — hand-rolling, specialization, and "reinventing
wheels" are the work; never outsource the core to a dep or golf it down for
line count. Test: "deliverable, or incidental to the deliverable?" Incidental
→ minimize. Deliverable → build deliberately. Correctness, error handling,
and security are never laddered away at either layer.

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

## Model billing — Max plan only, never API credits

Every model call (sessions, spawned agents, experiment harnesses shelling
`claude -p`, tern SDK dispatch) runs on the Anthropic Max subscription via CLI
auth (`claude.ai` OAuth). NEVER introduce `ANTHROPIC_API_KEY` / `apiKeyHelper` /
API-credit billing into env, settings, or harness code — no key on the machine
is the structural guarantee. `total_cost_usd` in CLI JSON output is API-price
ACCOUNTING (informational), not billed credits — label it "API-equivalent
accounting" when reporting experiment costs.
