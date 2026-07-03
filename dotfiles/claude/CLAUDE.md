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

Tier = the task's REASONING DEMAND, never its importance. Shape triage —
execute / implement / integrate / design / invent — maps onto the stack:
**sonnet-low** discovers → **sonnet-medium** builds → **opus-high** judges
→ **fable-xhigh** plans/analyzes the hardest; coordinator stays Opus/Fable
(session effort high). Opus steps DOWN to medium only for scoped,
well-specified work (e.g. implementation escalated from sonnet); up to
xhigh for long-horizon agentic runs. **max is never a default** at any
tier: official guidance gates it on measured xhigh saturation; documented
overthinking failure modes. Haiku is
OFF the stack (single-shot bulk classify only — details in doc). Two hard
laws: **pin BOTH dials on every spawn** (harder ⇒ escalate the MODEL, never
sonnet high/xhigh); **Fable analyzes, never default-implements** (coding ≤
Opus; in a Fable session PIN implementation spawns to opus/sonnet). Spawns
compose role + posture + model-delta blocks from praxis/ — cache, don't
re-derive; tern spawns get the delta automatically.

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
