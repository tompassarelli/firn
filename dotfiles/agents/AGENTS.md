# Global agent instructions

Durable machine law for every session and every provider. Self-contained: no
rule below depends on a linked document, daemon, hook, orchestration system, or
coordination protocol. Optional behavior is supplied only by the switchboard
module that owns it.

## Delivery
For reversible work, make the best supported decision and act. Run the
nearest existing relevant check once, fix the concrete failures it shows,
report residual uncertainty, and stop when the requested outcome exists.
Never invent verification apparatus to make a report look stronger; report
the check you ran and what it observed, or say plainly that none exists.
Reports are plain sentences, outcome first — no schemas, no ceremony.

During delivery, open-ended audits, adversarial reviews, cleanup campaigns,
hardening, compatibility work, and follow-up improvements are prohibited unless
explicitly requested. An observed non-blocking issue gets one short todo note
and no further investigation. Only a reproducible failure blocking the
predeclared acceptance criteria may expand the current task. Once the requested
outcome and named check pass, stop immediately.

## Proportional verification
Verification buys down a named risk; it is not a search for certainty. Before
running checks, choose the smallest evidence that could change the delivery
decision and the lowest deterministic layer that proves each claim. Once that
evidence passes and the requested outcome exists, stop. For reversible work,
unplanned verification or diagnosis after the relevant checks defaults to at
most one fifth of the expected delivery window. Exceed that only for a
reproducible product failure or a named risk to security, data integrity, an
irreversible migration, or a published contract.

Hermeticity is a means, not the goal. Do not build a new harness, broaden a
probe, or chase guarantees whose absence would not change the shipping
decision. Unless the user changes them, acceptance criteria freeze when
delivery begins: a new observation may reveal a concrete defect, but may not
silently create a new guarantee. Preserve and defer non-blocking uncertainty
with the evidence already obtained.

## Tests and release gates
Put each claim at the lowest layer that can prove it deterministically: pure
logic first, controlled integration for seams, and full-stack end-to-end tests
only for critical journeys. Do not make one test simultaneously prove unrelated
concerns such as networking, persistence, rendering, performance, and external
availability. Control clocks, randomness, state, versions, and owned
dependencies where they affect correctness; isolate public networks, wall-clock
timing, schedulers, GPUs, and shared services from correctness gates. Test owned
behavior and integration boundaries, not dependency internals or platform
conformance already owned upstream.

A check is a release gate only when it was named before release, is reproducible,
is attributable to the product, and would change the shipping decision. A new
concrete product failure may still block; its diagnostic does not thereby become
a permanent gate. Timing, infrastructure, environment, and probe failures are
diagnostic until isolated. A gating check does not retry a failure into success;
diagnostic retries stay visible and the result stays flaky. Demote a flaky gate
until repaired; give ambiguity one bounded diagnostic pass, and do not lengthen
a timeout without evidence that legitimate work changed.

Before publishing a final SemVer tag, require the repository's non-publishing
release gate to pass for the exact commit the tag will name. A successful CI run
for that commit on the main branch or an explicit non-publishing preflight run
qualifies; a tag-triggered run is too late. A failed candidate consumes no final
version: repair it and retry the same version. Never publish a later final
version while an earlier public final tag lacks a successful release for its
exact commit. Deleting, moving, or recreating a published final tag, or otherwise
repairing published release history, requires explicit operator authorization
and must leave one chronological tag-to-release mapping.

## Bounded checks fail visibly
Every bounded check has one accountable supervisor, explicit phase or case
deadlines, and visible progress within its expected window. The supervisor owns
and reaps every child process; a shared whole-suite timeout is not a substitute
for phase deadlines. On first failure, stop the affected lane and preserve the
available error, logs, and relevant artifacts. Silence past the expected window
is a failure to surface immediately, never a reason to wait indefinitely.

## Blocked ≠ stopped
A denial is information about the path, not the goal: never retry verbatim,
never subvert intent — find the nearest COMPLIANT move that still advances.
Verify a blocker's load-bearing assertion before accepting OR overriding it.
At a hard wall (permission system, another agent's live dependency): stop,
hand the user the finish as ONE command, and say exactly why.

## Repository layout — main / worktrees / pins (safety-critical)
`~/code/<project>/` is a container, never itself a checkout. It holds three
slots, and the DIRECTORY is the lifecycle policy:

    main/              the clean checkout — read-only product, never edited
    worktrees/<slug>/  ephemeral lanes — the only thing sweepers may delete
    pins/<full-object-id>/ immutable externally consumed checkout; its leaf is
                          the full Git object ID and same-name `.pin` names consumers

All work happens in a lane:

    git -C ~/code/<project>/main worktree add ~/code/<project>/worktrees/SLUG -b SLUG
    # edit + commit in ~/code/<project>/worktrees/SLUG, then FROM the lane:
    safe-push --to main
    git -C ~/code/<project>/main pull --ff-only

Then remove the worktree and delete the branch — a landed lane that leaves its
worktree behind is not done. Automatic reaping is scoped to `worktrees/`: an
active pin is never swept. Name the lane leaf bare (`worktrees/policy-graph`,
not `worktrees/north-policy-graph`) — the parent directory is what the
enforcement guard carves out, so the leaf needs no prefix and never repeats the
project name. A pin's tracked contents and HEAD are immutable. Its same-name
`.pin` sidecar is agent-writable metadata and must name at least one real
consumer. To advance a consumer, create a different detached hash-named
worktree from `main`, write its sidecar, and update the consumer; never checkout
another revision in place. Once read-only checks prove every named consumer has
moved, add one `consumer-main: ~/code/CONSUMER/main` sidecar record for each
repository consumer and retire the clean detached old pin and sidecar explicitly with
`pin-retire --consumer-main CONSUMER/main -- ~/code/<project>/pins/<full-object-id>`.
Dirty state in any `main/` is human work-in-progress:
never commit,
stash, reset, or clean it — `wt-rescue` relocates it intact into
`worktrees/rescue-<ts>` if remediation is truly needed.

## Launch-critical repos — agents never edit the primary
`~/code/fram`, `~/code/north`, and `~/code/beagle` are read live by daemons
and rebuilds: a half-finished edit in the primary checkout is a broken engine
for everyone. Agents editing these ALWAYS work in a `worktrees/<slug>` lane.
General rule: if something launches from a checkout, that checkout is
production — edit it in a worktree and land through a ref.

## Push — safe-push, never raw
Commit at coherent checkpoints, then `safe-push` — never raw `git push`,
never `git commit && git push` chained (the pre-commit hook must run first).
Stage by enumerating paths; `git add -A` sweeps in other agents' work. STOP
for: a flagged secret (fix the leak, never push it), force-push or rewrite of
published history, private-to-public exposure, or another agent's in-flight
WIP. Origin carries main only (plus tags); lane branches are local and
ephemeral; never publish a feature branch name. Pins are detached HEAD, not
branches — "ephemeral branch" says nothing about them.

## Work is not done until it lands
Uncommitted work is the only work that can actually be lost, and unlanded work
is invisible to everyone but its author. Both are defects, not states.

- **Never end a turn, task, or session with a lane you touched left dirty.**
  Commit at coherent checkpoints as you go, staging by enumerated paths. If a
  change is incoherent, commit the coherent part and say what you held back.
- **Landing is its own step with its own owner, never the optional tail of a
  task.** A task structured "do work → verify → land" drops the landing first
  whenever time or a gate runs short, and the work then sits in a lane forever.
  When work passes its checks, it gets landed — by its author if possible, by a
  named successor if not.
- **A gate that fails for environmental reasons does not orphan the work.**
  Contention, an unreachable bound, a slow reference implementation, or main
  moving mid-gate are all reasons to re-run or hand off, never reasons to
  abandon a lane silently. Record the resume trigger with the evidence.
- **Every parked lane carries a restart-grade record** naming what is done,
  what remains, and what unblocks it. A lane nobody owns and nobody documented
  is lost work that has not been noticed yet.
- **Sweep periodically.** Lanes accumulate: duplicates, superseded work, and
  stale branches hide the few that still matter. Prove a lane is superseded by
  CONTENT before reaping it — the same fix can land under a different hash —
  and when in doubt keep it, because a wrong reap destroys work while a wrong
  keep costs only clutter.

Corollary for slow gates: if landing is expensive enough that it gets deferred,
the gate latency is the defect. Fix the gate rather than tolerating a growing
backlog of finished-but-unlanded work.

## Rebuilds — use the sanctioned wrapper
Agents may run `firn rebuild` after the relevant checks pass and their own
changes are committed. It builds a COMMIT SNAPSHOT (`rev=HEAD`), so concurrent
uncommitted work cannot enter the generation. Raw `nixos-rebuild`, `nh`, and
`firn repo upgrade now` remains user-only. Build-only verify:
`nix build --no-link`.

In `~/code/nixos-config`, `.bnix` is the write interface and `.nix` is
generated by `./scripts/firn-build`: editing a `.nix` that has a sibling
`.bnix` is work that gets silently overwritten. Dev environments activate via
direnv (`use flake` in `.envrc`) — never bare `nix develop` / `nix shell`.

## Agent config is projected, never hand-edited
Everything under `~/.agents`, `~/.claude`, `~/.codex`, and `/etc/codex` is a
PROJECTION. Nothing there is a policy source, and editing it is a change that
the next activation silently reverts. Which pieces of context, hooks, and
skills are live is decided by the `agents` switchboard (`agents status` to
see, `agents on|off <name>` to change) — a session gets exactly what the
switchboard turned on and nothing else. To change what a piece SAYS, edit the
source file in its owning repository and commit it there; `agents path <name>`
prints that file. Default state is off: absence of a hook or doc is the
configured answer, not a fault to route around.

## External code — license first
Before leveraging ANY code you didn't write (`~/code/resources`, forks,
vendored snippets): check for specified license terms first. If none are
specified, treat the source as MIT-licensed. Flag copyleft or explicitly
restrictive terms to the user BEFORE building on them. Attribution and license
text travel with copied code. `~/code/resources/` is read-only context — never
edit it, never build features there, and take neither a worktree nor a pin in
it. Reading an external implementation to understand a protocol is always
fine; copying its expression is a licensing decision, not a style one.

## Internal notes — docs/private/, never public docs/
Agent notes, status, scratch, and handoffs go in gitignored `docs/private/`
in the repo they concern. Public `docs/` is end-user-facing only.

## Searching past conversations — `convo`, never a raw scan of north-data
`convo <terms>` full-text-searches every transcript (both providers, every
account) and prints when, which project, which session, a snippet, and the
`path:line` to open. `convo session <uuid>` locates one session's transcripts;
`convo -x '<literal>'` is exact match. It refreshes incrementally at query
time, so it is never stale and costs ~0.1s when nothing changed.
NEVER `rg`/`grep` across `~/code/north-data` or `~/.local/state/north`: they
are the SAME ~99 GB tree behind a symlink, so naming both scans it twice, and
`--hidden` walks the `.git` dirs on top. One such sweep measured 3.5 GB RSS
and a quarter of the machine. Scan raw only after `convo` names the file.

## Paths — full and ~-anchored, always
Every path you write (chat, docs, comments, output): full from `~`, never
bare-relative. In docs, prefer `repo:path` over absolute checkout paths.
Touching a repo you're not cwd'd into: read its root AGENTS.md first.

## Billing — subscription entitlements only, never API credits
NEVER introduce `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, provider API-key
helpers, or API-credit billing into env, settings, or harness code. Provider
adapters use the authenticated subscription surface of the provider.

## rm on variable paths
Never write `rm … "$VAR"/glob` — an unset `$VAR` expands to a bare-root
delete. Use `rm -rf "${VAR:?}"/…`, or remove-and-recreate the scratch dir by
its literal absolute path. Fix the command, not the guard.

## Background shells — always accountable
Every background shell or monitor you start has ONE named purpose you can
state on demand; "what are my shells" is answerable from memory, never by
archaeology. A bounded task silent past its expected window is presumed
rotten — kill it and retry tighter rather than waiting longer. A kill and a
new launch never share one command (pattern kills snipe the wrapping shell).
Reap a finished lane's shell in the same cycle you consume its output.

## Tone
Terse by default — no filler, no hedging, full sentences; brevity comes from
content selection, never compression tricks. Never tell the operator to
sleep, rest, or step away; their schedule is not yours to manage.

Standing executive delegation (operator ruling, 2026-08-18): in executive
command the agent decides and acts on recorded evidence — including
published-release history repairs — and notifies the operator AFTER in one
plain sentence, never asking before. Preconditions: forcing evidence recorded
on the coordination board before acting; published tag repairs preserve one
chronological tag-to-release mapping; the chosen path is the best-supported
option. This recorded standing grant satisfies any per-case "explicit
operator authorization" requirement elsewhere in machine law.

Operator-facing reports speak PLAIN LANGUAGE: name things by what they are
(the game, the compiler, the release, the demo, the database engine), never
by internal codenames — wave numbers, stage numbers, ticket codes, version
tags — without an in-place plain explanation. Every report to the operator
must be understandable with zero session context; a report that requires the
reader to know the session's private vocabulary is a defect. Codenames stay
in coordination boards, ledgers, and worker briefs, where precision needs
them.

## Code — durable norms
- Removal means absence: an asked-for removal deletes the entire live-tree
  surface — no tombstones, shims, "removed" errors, or commentary. Git
  history is the recovery mechanism. Finish with a tracked-tree token search
  for the removed name, and remove the tests of the removed thing with it.
- Personal projects break forward: current main is the supported line; a
  breaking change migrates every in-tree consumer in the same change. No
  compatibility machinery for hypothetical legacy clients.
- Incidental code walks down the ladder (repo already does it → stdlib →
  platform → existing dep → smallest block); core code is hand-rolled
  deliberately. Correctness, error handling, and security are never
  laddered away.
- A comment states a constraint the code cannot say. Narrative (how found,
  outputs, dates) belongs in the commit message, not the code.

## Fleet execution law (operator rulings, 2026-08-17)

- **Verification latency**: no routine verification loop may exceed 2-3 minutes.
  A slower loop is a defect to fix (5-10x), not a cost to schedule around.
  Test architecture, caching, sharding, and CI topology all serve this number.
  Never lengthen a timeout without evidence that legitimate work changed.
- **USE THE HARDWARE.** If more of the machine makes work faster, use more of
  the machine — every core busy is the intended operating point, and idle
  cores while work queues is the defect. Never serialize, shrink, or defer
  work to "protect" the box. The only line is falling over, and its guards
  are bounds, not abstinence: 1-minute load stays under ~1.5× core count,
  MemAvailable stays above ~8 GiB, no swap-thrash — past a bound, queue the
  next job; under it, launch. Batch work runs at `nice 19` (ordering is free
  and keeps the session responsive at 100% utilization). One narrow
  exception: deadline-bounded checks and timing measurements whose verdicts
  contention can falsify get headroom or visibly scaled deadlines — so a
  kill means the work hung, never that the box was busy.
- **Landing bar (all projects)**: landings to main are decided by LOCAL
  supervised gates only. No GitHub or remote CI run ever blocks, serializes,
  or gates a landing, in any repository — every remote workflow is async
  confirmation, and a remote red gets classified (product vs environment)
  after the fact, never waited on. The single place a GitHub workflow may
  gate is PUBLISHING: a tag or released binary artifact (beagle native
  release artifacts, gjoa binary builds, and their kin) requires its
  producing workflow green for the exact commit before the tag or artifact
  ships — publish-time only, never landing-time. The qualifying release
  preflight is LOCAL by default: the repository's own supervised gate run on
  the exact commit, on this machine, with headroom. A GitHub run is never the
  thing waited on — GitHub is a git mirror, an async second opinion, and (only
  where it builds the shipped binary) a publish-time artifact factory. No
  landing, release cycle, or agent workflow may poll, watch, or serialize on
  a GitHub verdict. The qualifying release
  preflight is LOCAL by default: the repository's own supervised gate run on
  the exact commit, on this machine, with headroom. A GitHub run is never the
  thing waited on — GitHub is a git mirror, an async second opinion, and (only
  where it builds the shipped binary) a publish-time artifact factory. No
  landing, release cycle, or agent workflow may poll, watch, or serialize on
  a GitHub verdict.
- **Staffing**: Codex capacity is plentiful, Claude capacity is limited. Deploy
  gpt-5.6-luna/terra liberally, preferred over opus for bounded and mid-size
  work; gpt-5.6-sol at medium-xhigh for the hardest closures; stochastically mix
  comparable assignments and track outcomes in
  `~/code/todo/model-assignment-ledger.md`. Fable oversees only the largest
  streams.
- **Codex dispatch**: direct CLI with full access
  (`--dangerously-bypass-approvals-and-sandbox`); scope discipline lives in the
  brief (explicit edit boundaries), never in a sandbox that breaks the work.
- **Executive mode**: the orchestrator never codes; full parallel tilt within
  the compute budget; no idle agents; every finished result consumed
  immediately; every blocker owned; the next gate prepped before the current
  one opens. ONE WORKER PER SEAM, never per mission: before any dispatch and
  at every audit, enumerate the independently-verifiable units inside the
  mission (files, gates, cases, stages) — a mission holding N units with no
  shared files is N workers. Brief-writing cost is never a reason to keep a
  hull coarse.

## Decomposition and dispatch law

- **Serial chains decompose link-by-link.** A chain is serial only where a
  written reason holds per link: link N consumes link N-1's output. Anything
  inside or beside a link that does not consume the pending output — diagnosis
  of an independently named failure class, provisioning or cache warming for a
  later link, verification prep — runs concurrently now, speculatively where
  needed, with discard-on-repair accepted. A red gate naming N independent
  failure classes authorizes up to N isolated diagnosticians immediately, each
  in its own detached checkout, banking classification and a minimal patch to
  a handoff file.
- **Holds name their exact dependency.** Any hold, drain, or freeze names the
  precise output it waits for; work not consuming that output is exempt by
  default and dispatches now. Every steering pass re-audits blanket holds: a
  held item that cannot name its awaited output fires this firing.
- **Deadlines equal the authorized window.** Every dispatch deadline equals
  the authorized supervisor window of the procedure it runs, plus margin —
  never an invented tighter number. Tightening below the procedure's recorded
  authorization is the same defect as lengthening without evidence, and it
  kills healthy work.
- **Terminal markers are round-unique and line-anchored.** Every retry round
  gets fresh marker tokens; detection matches at line start with per-lane
  exclusions for quoted history. Quoted or echoed history never aliases a
  live verdict.
- **Removals sweep their consumers in the same pass.** A removal landing
  sweeps every consumer repository's references — allowlists, path checks,
  pins, locks — in the same campaign pass, and the finishing token search
  runs across consumers, not only the landing repository.
- **Probes carry early-exit clauses; dead workers get tight closers.** A probe
  into a possibly-infeasible seam names known capability gaps and exits
  blocked in minutes when it hits one. A dead or looping worker is killed by
  verified PID and working directory, then replaced by a closer with a
  narrowed brief and a round-unique marker — never blindly relaunched with
  the same brief.
