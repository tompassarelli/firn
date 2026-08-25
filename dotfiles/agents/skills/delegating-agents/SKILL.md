---
name: delegating-agents
description: >-
  Decompose, route, dispatch, supervise, steer, and settle delegated agent
  work. Use whenever creating sub-agents or worker lanes, choosing an agent
  model or subscription account, running parallel seams, waiting on another
  actor, setting worker deadlines, replacing a stalled worker, or operating in
  executive orchestration mode.
---

# Delegating agents

Delegate only when independently verifiable work can progress concurrently.
Keep tightly coupled work with one closure owner, who owns the outcome rather
than a serial list of defects.

## Establish continuity and seams

Create or update a restart-grade record in `~/code/todo/` before delegation and
give every execution attempt its shared forecast/staffing receipt before launch.
Enumerate the mission's independent units—files, gates, cases, or stages—and
assign one worker per seam, not one worker per mission. A serial edge is valid
only when the later seam consumes the earlier seam's output; write that exact
dependency. Dispatch everything else now, including safe preparation beside a
held edge. Explore and evaluate are read-only by default and need no lane;
create one only when a write is admitted.

State the closure posture and its terminal evidence: explore has an observation
or capability gap, evaluate has a decision and its evidence, deliver has the
owned change and named check, preserve has a named artifact/owner/recovery
condition, and prune has proved absence from its named live consumers. Do not
turn a posture into a universal ceremony.

Give every brief explicit read/write boundaries, terminal evidence, the
existing check it owns, an early-exit clause for known capability gaps, and the
authorized supervisor window plus margin. Capability and policy own standing
prohibitions; a brief records only its scoped exception. Never invent a tighter
deadline or lengthen one without evidence that legitimate work changed.

Budget inherited context as a dispatch input. For collaboration workers,
default `fork_turns` to `none` or the smallest recent slice containing facts
that authoritative artifacts do not already preserve; use `all` only when the
task materially depends on uncaptured conversational decisions. Put task-local
facts in the brief and reference restart records, exact commits, paths, and
named skills instead of pasting instruction bodies or undifferentiated strategy
packets. The worker still discovers and reads every applicable instruction,
but loads the minimum applicable set completely through bounded sequential
reads rather than one aggregated instruction-loading call.

## Stage research before synthesis

For research that feeds one integrated artifact, name one closure writer before
fan-out and start that writer immediately. Have the owner inventory and dedupe
composite sources against their constituents, name the acceptance contract,
and decompose only by independent decisions or artifacts. Never partition
research by headings, line ranges, or an exhaustive-coverage matrix.

Start with at most two read-only shadows. Every added worker must own one newly
exposed independent decision or proof obligation, and its brief must state how
that result changes or shortens the critical path. Require one compact decision
card with exactly four fields: decision or proof, evidence, conflict, and
recommendation. Bound each field to one short paragraph or list of exact
references containing only closure-relevant content; raw narration and
chronology are forbidden. Feed each card to the writer as it arrives; never
wait for every scout without an exact dependency. Interrupt and reap a scout as
soon as its evidence is consumed.

Keep broad parallelism for genuinely independent deliverables. For one final
synthesis, keep one closure writer through integration. Multiple writers are
valid only for independent artifacts with separately verifiable acceptance
gates.

Before dispatch, set two non-substitutable admission budgets: elapsed
critical-path wall time and summed agent execution time across the closure
owner and every delegated worker. Admit a topology only when its forecast fits
both; unused wall budget never pays for excess agent time. At each stage
boundary, compare both actuals with forecast and widen only for a newly exposed
independent obligation when the remaining plan still fits both budgets. At one
times planned aggregate agent time without a closure candidate, stop adding
workers and replan or consolidate. At two times either the wall or agent-time
estimate, interrupt and rebrief; never extend the estimate in place. Settle both
actuals through the existing attempt receipt.

Attempts subdivide accounting; they never reset the operator outcome's clock.
A replacement commander, narrower rebrief, successor program, renamed phase,
or new attempt ID inherits the same acceptance contract and cumulative wall
and agent actuals. At two times the original outcome budget without an accepted
operator-facing artifact, stop that program and deliver the best supported
result or capability gap. Admit another budget only for a genuinely new
operator goal or a newly exposed independent obligation whose changed work is
explicitly priced; never obtain more time by renaming the continuation.

## Ratchet development speed

Use a measured speed ratchet when uncertainty or critical-path risk makes
speculation worth its cost. `verification` remains the sole owner of compile,
test, and development-loop pricing; reuse its expected wall time and telemetry
instead of inventing a second performance ritual. Choose the lowest level that
can change the decision:

0. **Closure owner** — one worker owns the implementation and acceptance gate.
1. **Shadow** — parallel, read-only reconnaissance, review, or test design;
   no competing implementation is written.
2. **Race** — independent worktrees implement a critical-path seam, or a seam
   whose implementation is high-variance, silent/overrun, or materially
   uncertain.
3. **Portfolio** — several lanes only for genuinely distinct algorithms or
   architectures, not cosmetic rewrites of one approach.

Escalate only when the expected critical-path saving exceeds duplicate setup,
merge, review, and compute cost and the work advances that path. A compact
heuristic is `net gain ≈ P(faster winner) × (owner finish − raced finish) −
(setup + merge + review + compute)`; use evidence and a conservative range,
not false precision. Inspect a nearly complete candidate before duplicating it;
salvage or repair when that is faster than a fresh lane.

Every race names its winner condition up front, uses independent worktrees and
the same acceptance gate, and counts only verified integration as progress.
Candidate branches are hypotheses, not completed work. Consume the first
verified winner, interrupt and reap every loser immediately, and preserve only
useful unique evidence. De-escalate when risk drops. Never use a race to bypass
serial semantic ownership, safety boundaries, or available machine headroom.

## Budget review without losing deferred work

At admission, choose the attempt's `review_budget`: `none` for a bounded,
reversible seam whose owner evidence is sufficient; `owner` for ordinary
deliverable review; or `independent` when the change, uncertainty, or requested
assurance merits a separate reviewer. This is a proportional budget choice, not
a promise that every completion receives a standing reviewer or a subjective
quality score. An independent reviewer receives one exact commit, the intended
invariants, and a finding/disposition boundary; choose its model from the same
quality floor and task difficulty rules as any other assignment.

When a reviewer finds a real defect, link the finding to the exact commit and
record its review-repair time actual in the owning attempt. When a consciously deferred gap
matters, record a concrete path, invariant, severity, owner, and exit condition
as `[[quality_debt]]` in the todo record. Do not reopen or re-polish settled
code absent a changed commit, a new finding, or a named assurance reason.

## Route models and accounts from evidence

Honor a user-pinned provider, account, model, and reasoning level exactly.
Otherwise choose model, tier, and deliberation from task difficulty; choose
ceremony and authority separately from blast radius and reversibility. Use the
live configured dispatch surface and provider catalog rather than remembered
availability. An omitted model in a spawn schema is route metadata, not
evidence that a model is unavailable.

Treat North presets as templates, not cages: compose a justified custom route
when its model/deliberation and authority choices are recorded. Prefer
subscription-backed Codex Luna or Terra for bounded and mid-sized leaves and
Sol for hard integration. For a direct OpenAI lane, compose the North payload,
pin model and reasoning on `codex exec`, give the workstream a positive integer
estimated-token budget, and dispatch through `north account dispatch
--assignment <id> --estimated-tokens <n> -- exec ...`. The entry point refreshes
subscription usage, projects each eligible account's utilization from its
observed percentage plus outstanding token reservations through a versioned
per-account/window calibration, records the selected account, atomically
reserves the estimate, and launches `codex as <account-id>` itself. Completion
reconciles the reservation to observed actual tokens; cancellation releases it;
stale reservations expire explicitly. Live agent count is a hard safety cap,
not a substitute score. Round-robin breaks only near ties in projected usage.
Inspect the same decision without launching with `north account dispatch
--dry-run --estimated-tokens <n> --json`. Missing fresh usage, a usable
calibration (including its labeled conservative fallback), the token estimate,
or an eligible account fails closed. Dispatch the direct CLI with full access
(`--dangerously-bypass-approvals-and-sandbox`) and put its scope boundary in the
brief. If availability is uncertain, inspect installed configuration and run
one fresh subscription-backed probe. The bootstrap billing boundary still
applies.

Raw `Agent`, `Task`, Workflow, or collaboration `spawn_agent` calls have no
subscription-account selector and are not fleet-dispatch surfaces. A commander
must not use them when an account is being allocated; use the account-dispatch
entry point above. User-pinned single-account native work remains outside this
fleet rule.

Every authorized delegated worker runs with unrestricted filesystem and network
access and without an approval sandbox. For direct Codex lanes, always pass
`--dangerously-bypass-approvals-and-sandbox`. Collaboration `spawn_agent` has no
permission field and inherits the parent session, so admit it only after the
parent permission profile is unrestricted. If an available dispatch surface
cannot provide that authority, report the exact capability gap instead of
silently launching a constrained worker. Full execution authority does not
broaden the worker's brief, repository lane, publication authority, credential
boundary, or standing safety rules.

The account-dispatch evidence is live-only commander/operator evidence. It
never becomes Store-authoritative autonomous routing and grants no write or
publication authority; the brief and lane admission still do that. Record the
observed outcome in `~/code/todo/model-assignment-ledger.md`; the API's machine
assignment already records the selected account. Also put the exact model,
reasoning, route, role, and assignment ID on the owning attempt so its terminal
receipt can improve model selection rather than merely preserve a dispatch log.
Use settled samples to compare delivery, review findings, and repair tax by
seam/model; do not pretend one receipt establishes an economic ranking.

## Admit before dispatch

Mechanically admit model, applicable policy, repository identity, entrypoint,
environment, write authority, and a viable supervisor. A write needs an owned
lane and no conflicting owner; an unadmitted item remains read-only or queued,
not implicitly authorized.

## Use the machine without falsifying checks

The logical DAG says which independent seams may progress. Physical capacity is
separate: use a named compute semaphore when concurrent work could falsify a
timing or resource verdict. Start ready work with fresh CPU/memory headroom,
balanced activity, and round-robin fairness; queue only the constrained compute
edge. Keep one-minute load below roughly 1.5 times the core count, available
memory above roughly 8 GiB, and avoid swap-thrashing. Batch compute runs at low
scheduling priority. Preserve headroom for
deadline-sensitive checks and timing measurements whose verdict contention
could falsify.

Use `verification` to select and interpret checks; do not duplicate its landing or
publication gate rules in worker briefs.

## Supervise every process and worker

Keep a live ledger in which every background shell and worker has one named
purpose, owner, expected progress point, and reap action. Consume a completion
immediately. Silence past the authorized window is a visible failure: verify
the PID and working directory, stop the process, preserve its evidence, and
replace it only with a narrower closer. Never relaunch the same brief blindly
or combine a kill and replacement launch in one command.

Agent Bash background work runs as `run-bounded <duration> -- <command>`, never
as bare `nohup`, `setsid`, `disown`, or an unmanaged `&` job. The duration is
explicit and cannot exceed 24 hours. `run-bounded` owns a transient cgroup and
PID namespace, so owner death and timeout both reap every descendant; all such
jobs share a 48 GiB hard ceiling without reducing compiler parallelism.

Fresh retries use round-unique, line-anchored terminal markers so quoted
history cannot impersonate a live verdict. A probe that reaches a known
capability gap exits within minutes and reports the gap. The same result three
times is a finding, not a polling target.

If the supervisor fails before its child starts, classify infrastructure rather
than a product verdict. When the user bus is unavailable, an explicitly approved
child-free diagnostic may run foreground under `timeout <duration> -- command`;
record that fallback and do not infer child supervision or product success.

## Keep feature liveness safe

Required feature liveness is fail-closed: do not automate feature work or
activation from a missing, stale, or unadmitted signal. The escape is a bounded
repair seam that restores the signal; direct human control may act on the
classified evidence. Neither live-only data nor a failed liveness probe grants
automated authority.

## Steer and settle

Re-audit every blanket hold: if a held seam cannot name the exact output it
awaits, release it. When a removal is delegated, sweep registrations,
allowlists, paths, pins, locks, tests, and consumer repositories in the same
campaign, then run the final token search across those consumers.

The parent retains integration and semantic settlement authority. Consume each
result and decide its verification, review, publication, verdict, race, debt,
and exact lane state. At a terminal worker boundary, emit the `todo`
SettlementCard and delegate the mechanical update through `settle-work` by
default with `fork_turns = none` or equivalent minimal context. The card,
owning record, and named authorities replace product history. Settle directly
only when no admitted worker slot exists or dispatch costs more than the
bounded bookkeeping.

The settler applies only exact card-supplied terminal TOML fields, writes the
deterministic keyed estimate receipt, and applies the exact owner-supplied lane
state after record, attempt, and lane identity checks. It cannot integrate,
review, publish, invent evidence, rewrite Markdown prose, operate on a lane or
branch, or infer disposition. The parent updates the restart record's prose and
uses repo-safety to land and reap verified work. A worker denial changes the
path, never the goal; do not retry verbatim or route around standing law.

In executive mode, decide and act on recorded evidence, keep every ready seam
owned, and notify the operator after the fact in plain language. The standing
grant includes published-release-history repairs only when forcing evidence is
recorded on the coordination board, the chosen path is best supported, and one
chronological tag-to-release mapping remains. This does not broaden safety
authority or permit unrelated mutation.
