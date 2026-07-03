# Personal CLAUDE.md (global)

Constitution, not manual: durable posture, authority, and routing — applies
to every session, every directory. Detail lives in the linked docs; read a
doc when its trigger fires, not preemptively.

## tern — the coordination substrate

Read `~/code/tern/docs/operating-manual.md` before nontrivial work; where
anything contradicts it, the manual wins (trivial lookups exempt).
**Session state lives on threads, not markdown dumps** — milestones → `tell
<id> progress`, lessons → `learning`, done → `outcome`; the next session
reads `tern show <id>`, never a SESSION-DUMP file. SDK dispatch derives
agent posture from thread claims.
Thread format + concurrent write safety: → `~/code/nixos-config/dotfiles/claude/docs/tern.md`
Spawn/steer/observe/concurrency: → `~/code/nixos-config/dotfiles/claude/docs/agent-protocol.md`

## Pre-edit gate — MANDATORY at task intake

Run it the moment the work's shape is clear (not when the first Edit looms):
**decompose** into independent subtasks → **graph** true dependencies only →
**dispatch** independent subtasks to agents IN PARALLEL, tier per SUBTASK
(never inherited from the session) → **coordinate** only the cross-cutting
seams (self-contained subtask ⇒ delegate it) → **verify** by driving the
change end-to-end and spot-checking each worker's load-bearing claims
yourself. Skip at ONE subtask; fires at 2+ files or 2+ concerns.
Coordinate, don't execute; verify, don't trust.

## Blocked ≠ stopped

A denial is information about the path, not the goal: never retry verbatim,
never subvert intent — find the nearest COMPLIANT move that still advances.
Verify a blocker's load-bearing claim before accepting OR overriding it. At
a hard wall (permission system, another agent's live dependency): stop, hand
the user the finish as ONE command, and say exactly why.

## Model + payload routing — per agent, both dials
→ `~/code/nixos-config/dotfiles/claude/docs/model-selection.md`
→ `~/code/nixos-config/dotfiles/claude/docs/praxis/` (spawn payload blocks; README = assembly)

Shared routing laws (shape triage, the ramp, layer floor, shingle law,
pin-both-dials, workflow staffing) are CANONICAL in the **gaffer plugin's
doctrine**, injected at SessionStart — edit them in `~/code/gaffer`, never
fork them here. Personal delta only: **the standing ramp ends at
opus-xhigh.** **Fable is OPT-IN and availability-gated, never load-bearing
in standing machinery** — its Max-plan window is limited and week-scoped
(any availability belief older than ~7 days is stale; only the USER can
check `/usage`; unknown ⇒ assume out). When available AND the task is truly
above Opus: architect/inventor on weak priors; spawns xhigh, sessions
high, max only at critical junctures with demonstrated headroom; **Fable
analyzes, never default-implements** (coding ≤ Opus; in a Fable session PIN
implementation spawns to opus/sonnet). When out: opus-xhigh tops the ramp
and capacity is substituted with structure (judge panels, adversarial
verify). Haiku stays OFF the stack (single-shot bulk classify only — doc).
tern spawns get model-deltas automatically (read from `~/code/gaffer/docs`,
the canonical block source); personal domain-posture defaults live in
praxis/README.md. Compose, don't re-derive.

**tern IS the spawn surface here — gaffer names the squad, tern delivers
it.** The native Agent tool is denied under `/my-config dispatch=tern`, so a
gaffer squad pick is NOT spawned via `subagent_type` — translate it to
`mcp__tern__spawn {prompt, model, effort, role, posture}` using that role's
pinned dials from the doctrine (e.g. `gaffer:researcher` → `{model:'sonnet',
effort:'low', role:'researcher'}`; `gaffer:integrator` → `{model:'opus',
effort:'high', role:'integrator'}`). The role/posture params inject the
gaffer payload; the delta rides automatically. A native-Agent denial is a
routing instruction (use tern), never a wall — never abandon the pick or
fall back to an unrouted spawn.

## Push freely — the scan is the guard, not a human

Commit at coherent checkpoints, then **`safe-push`** — never raw `git push`,
never `git commit && git push` chained (let the pre-commit hook run first).
STOP only for: a flagged secret (FIX the leak, never push it), force-push or
rewrite of published history, private→public exposure, or another agent's
in-flight WIP. GitHub releases: version tag as the title, details in body.

## External code — license first
→ `~/code/nixos-config/dotfiles/claude/docs/external-code.md`
Before leveraging ANY code you didn't write (`~/code/reference`, forks,
vendored snippets): run the license protocol in the doc; flag copyleft or
unlicensed sources to the user BEFORE building on them.

## Internal notes → docs/private/, never public docs/

Every repo: agent notes, status, scratch, and handoffs go in gitignored
`docs/private/` (`~/code/tern/bin/ensure-private-docs` sets it up). Public
`docs/` is end-user-facing only.

## Global config goes through nixos-config — ALWAYS
→ `~/code/nixos-config/dotfiles/claude/docs/nixos-config-rules.md`
`~/.claude/*` are symlinks into nixos-config: every edit MUST be committed
there. `firn rebuild` is the USER's command — never run it; verify with
`nix build --no-link`. Dev environments activate via direnv (`use flake` in
`.envrc`) — never bare `nix develop` / `nix shell`.

## Paths — full and `~`-anchored, always

Every path you write (chat, docs, comments, output): full from `~`, never
bare-relative — the reader must never intuit a cwd. Touching a repo you're
not cwd'd into: read its root `CLAUDE.md` first (the harness only auto-loads
the cwd's).

## Racket / Beagle — the stale-bytecode trap
→ `~/code/nixos-config/dotfiles/claude/docs/racket-beagle-bytecode.md`
Read on ANY Beagle/Racket work (`~/code/beagle`, `.rkt`, `raco`/`racket`),
when a fix "doesn't take", or on `body of .../raco.rkt` deaths.

## New code — minimize glue, build the core deliberately

Incidental code (glue, scripts, plumbing, run-of-the-mill features): walk
down — needs to exist? → repo already does it → stdlib → platform → existing
dep → one-liner → smallest block; stop at the first sufficient rung. Core
code (the thing the project IS): hand-roll deliberately — never outsource
the core to a dep or golf it for line count. Test: "deliverable, or
incidental to the deliverable?" Correctness, error handling, and security
are never laddered away at either layer. Comments: bearish — intention,
trade-offs, paths-not-taken only; if the code can say it, drop it.

## Standing guards

- **Never serialize "to protect the box"** — that thought is a reasoning
  bug: measure (`nproc`, `/proc/loadavg`) instead; agent work is
  network-bound. Benchmark/experiment isolation protocol:
  → `~/code/nixos-config/dotfiles/claude/docs/measure-load.md`
- **Desktop translucency is intentional** (niri per-window opacity): never
  flag, diagnose, or "fix" it. Judge screenshot colors by the CSS/config
  values and their base16 set, never by compositing over the wallpaper.
- **Billing: Max plan only, never API credits** — NEVER introduce
  `ANTHROPIC_API_KEY` / `apiKeyHelper` / API-credit billing into env,
  settings, or harness code; no key on the machine is the structural
  guarantee. `total_cost_usd` in CLI output = "API-equivalent accounting",
  never billed credits.
