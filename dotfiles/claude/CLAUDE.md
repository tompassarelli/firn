# Personal CLAUDE.md (global)

Constitution, not manual: durable posture, authority, and routing — applies
to every session, every directory. Detail lives in the linked docs; read a
doc when its trigger fires, not preemptively.

## north — the coordination substrate

Read `~/code/north/docs/operating-manual.md` before nontrivial work; where
anything contradicts it, the manual wins (trivial lookups exempt).
**Session state lives on threads, not markdown dumps** — milestones → `tell
<id> progress`, lessons → `learning`, done → `outcome`; the next session
reads `north show <id>`, never a SESSION-DUMP file. SDK dispatch derives
agent posture from thread facts.
Thread format + concurrent write safety: → `~/code/nixos-config/dotfiles/claude/docs/north.md`
Spawn/steer/observe/concurrency: → `~/code/nixos-config/dotfiles/claude/docs/agent-protocol.md`

## Billable work — clock or it didn't happen

**Any edit under `~/code/client/**` is billable and MUST run against a live north
clock on a thread linked to its Linear ticket.** This is enforced mechanically —
`north-clock-guard` (PreToolUse) DENIES the edit if no clock is running — because
prose here already failed once: ~22h of MSA work shipped with zero logged time
and had to be reconstructed by hand for an invoice. Don't wait for the deny:
**at intake on client work, derive the ticket from the branch (`msa-NNN` →
`MSA-NNN`), find-or-`capture` its thread (`owner msa`, `linear MSA-NNN`, `rate`),
and `north clock start` it BEFORE the first edit.** One clock at a time; `clock
stop` on context switch. Billing is derived, never invented: worklog =
`north-timelog`, invoice state machine = `north-invoice` (uninvoiced → invoice-sent
→ invoice-paid). Bypass only deliberately (`north config guards off`, or launch with `CLAUDE_NO_AUTHORING_HOOKS=1`).

## Pre-edit gate — MANDATORY at task intake

Run it the moment the work's shape is clear (not when the first Edit looms):
**decompose** into independent subtasks → **graph** true dependencies only →
**dispatch** independent subtasks to agents IN PARALLEL, tier per SUBTASK
(never inherited from the session) → **coordinate** only the cross-cutting
seams (self-contained subtask ⇒ delegate it) → **verify** by driving the
change end-to-end and spot-checking each worker's load-bearing assertions
yourself. Skip at ONE subtask; fires at 2+ files or 2+ concerns.
Coordinate, don't execute; verify, don't trust.
**The supervisor never blocks (2026-07-10, supersedes fork-by-default): the
user talks to a listener, never a worker.** EVERY work request delegates to a
lane — the only decision is the CONTEXT DIAL: needs this session's context ⇒
fork-of-me (composed context brief attached, `context:all`); ad-hoc ⇒ fresh
lane, right-sized model, no baggage (`context:none`). Pick the dial yourself;
never hold work inline because it seems quick. Inline is ONLY: answering from
context, reading, verifying delegated work, and the coordination acts
themselves (spawn/steer/capture/push). `/delegate [context:all|none] <task>`
(shell: `north delegate`) is the forcing form for when the automatic behavior
slips — its existence is a bug report against this paragraph.

## Blocked ≠ stopped

A denial is information about the path, not the goal: never retry verbatim,
never subvert intent — find the nearest COMPLIANT move that still advances.
Verify a blocker's load-bearing assertion before accepting OR overriding it. At
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
north spawns get model-deltas automatically (read from `~/code/gaffer/docs`,
the canonical block source); personal domain-posture defaults live in
praxis/README.md. Compose, don't re-derive.

**north IS the spawn surface here — gaffer names the squad, north delivers
it.** The native Agent tool is denied under `north config dispatch=north`, so a
gaffer squad pick is NOT spawned via `subagent_type` — translate it to
`mcp__north__spawn {prompt, model, effort, role, posture}` using that role's
pinned dials from the doctrine (e.g. `gaffer:researcher` → `{model:'sonnet',
effort:'low', role:'researcher'}`; `gaffer:integrator` → `{model:'opus',
effort:'high', role:'integrator'}`). The role/posture params inject the
gaffer payload; the delta rides automatically. A native-Agent denial is a
routing instruction (use north), never a wall — never abandon the pick or
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
`docs/private/` (`~/code/north/bin/ensure-private-docs` sets it up). Public
`docs/` is end-user-facing only.

## Global config goes through nixos-config — ALWAYS
→ `~/code/nixos-config/dotfiles/claude/docs/nixos-config-rules.md`
`~/.claude/*` are symlinks into nixos-config: every edit MUST be committed
there. `firn rebuild` is agent-runnable ONLY after `firn build` + `firn
validate` are green, your changes are committed, and no build input is
dirty — zero uncommitted `*.bnix`/`*.nix`/`flake.lock` in the tree (others'
dirty non-build files don't block); `firn update` and raw nixos-rebuild/nh
stay the USER's. Build-only verify: `nix build --no-link`.
Dev environments activate via direnv (`use flake` in `.envrc`) — never bare
`nix develop` / `nix shell`.

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
- **Banned vocabulary: "fleet"** for agent groups — dead pre-rename naming;
  the harness's own "FleetView" string is not our vocabulary and must not
  leak back in. Say lanes / agents / workers / spawns. (Ordinary English
  "fleeting" is fine.)
