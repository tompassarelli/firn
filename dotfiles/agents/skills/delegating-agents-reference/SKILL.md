---
name: delegating-agents-reference
description: >-
  Detailed delegation reference for fleet roles, research staging, dual
  budgets, speed-ratchet races, model and subscription-account routing,
  authority admission, supervision, terminal evidence, and settlement. Use
  after delegating-agents-distilled routes here.
---

# Delegating agents reference

`delegating-agents-distilled` owns the delegation decisions, boundaries, and
stop rules. This unit owns the detailed operating procedures.

## Brief and posture fields

Give each seam exact read/write boundaries, terminal evidence, nearest existing
check, early exit for capability gaps, authorized supervisor window and margin,
plus its cleanup path. Posture evidence is:

| Posture | Terminal evidence |
| --- | --- |
| explore | observation or capability gap |
| evaluate | decision with evidence |
| deliver | owned change and named check |
| preserve | artifact, owner, and recovery condition |
| prune | proved absence from named live consumers |

## Reusable role contracts

- **Commander:** owns a multi-seam DAG, continuity, supervision, product
  verdicts, settlement preparation, integration, and cleanup.
- **Continuity keeper:** applies exact commander-supplied facts to named restart
  records without inferring status, priority, or product truth.
- **Watchdog:** read-only advisory observer for one supervisor's bounded event
  windows; reports `healthy`, `late`, `failed`, `halted`, or `unknown` only to
  that supervisor and exposes its own degradation.
- **Settlement clerk:** fresh minimal-context worker applying one immutable
  SettlementCard through `settle-work-distilled`, then acknowledging and exiting.
- **Janitor:** removes only owner-released enumerated targets and proves their
  absence plus unaffected siblings.
- **Assurance worker:** independently reviews or verifies one exact artifact
  against its named gate and has no repair/publication authority unless granted
  separately.

Admit another reusable role only after repeated work demonstrates a distinct
trigger, authority boundary, evidence, and reap contract.

## Research before synthesis

Name and start one closure writer before fan-out. Inventory composite sources,
deduplicate constituents, define the acceptance contract, and decompose by
independent decisions or artifacts rather than headings or line ranges. Start
with at most two read-only shadows. Each added worker must expose a new decision
or proof obligation and state how it shortens closure.

Return one compact decision card with exactly: decision/proof, evidence,
conflict, and recommendation. Feed cards to the writer as they arrive and reap
each scout when its evidence is consumed. Multiple writers fit only independent
artifacts with separate gates.

## Dual budgets and speed ratchet

Forecast wall time and summed agent execution time independently. Compare both
at stage boundaries and widen only for a newly exposed independent obligation
that still fits. Replacement workers and successor programs inherit cumulative
actuals for the same operator outcome.

Use the lowest speed-ratchet level with positive expected critical-path value:

0. one closure owner;
1. a parallel read-only shadow;
2. independent implementation lanes racing one seam;
3. several lanes for genuinely different algorithms or architectures.

Estimate `P(faster winner) × (owner finish − raced finish) − (setup + merge +
review + compute)` with a conservative range. Inspect a nearly complete
candidate before duplicating it. Every race shares a named gate and winner
condition; only verified integration counts.

## Review and debt

Set `review_budget` to `none`, `owner`, or `independent` during attempt
admission. An independent reviewer receives one exact commit, intended
invariants, and a finding/disposition boundary. Record concrete findings and
review-repair actuals. Deferred quality debt names path, invariant, severity,
owner, and exit condition; do not use it as an unbounded polish queue.

## Model and account dispatch

Use live installed routing data. For the original calibrated direct-routing
defaults, subscription-backed Codex Sol is the meaningful-engineering
workhorse: medium ordinarily, high for complex/cross-cutting/weak-oracle work,
and low only for deterministic bounded work with a strong oracle. Luna and
Terra are auxiliary/mechanical routes; when directly selected without an
operator reasoning pin, their calibrated defaults are `xhigh` and `high`.
Explicit operator pins always win.

An account-allocated direct OpenAI lane needs a North payload, exact model and
reasoning, positive estimated-token budget, assignment ID, and:

```text
north account dispatch --assignment <id> --estimated-tokens <n> -- exec ...
```

Inspect selection without launch via:

```text
north account dispatch --dry-run --estimated-tokens <n> --json
```

The entrypoint refreshes subscription usage, projects observed utilization plus
outstanding reservations, chooses an eligible account, atomically reserves the
estimate, launches `codex as <account-id>`, and reconciles or releases the
reservation. Missing fresh usage, calibration, token estimate, or eligible
account fails closed. Direct CLI workers use
`--dangerously-bypass-approvals-and-sandbox`; collaboration workers require an
unrestricted parent profile. Record model, reasoning, route, role, assignment,
and settled outcome in the attempt and
`~/code/todo/model-assignment-ledger.md`.

## Admission and publication detail

Explore/evaluate work is read-only unless a lane is admitted. Product writes
need an owned physical lane; integration and publication need named authority.
For overlapping candidates, record exact base, owner, gate, integration owner,
and landing order. After one candidate lands, merge or rebase later work onto
that exact object, reconcile semantic conflicts, and rerun the affected gate.

Repository publication, settled attempts, explicit release, and reaped lane
and branch establish writer release. A failed acknowledgement is a coordination
defect to repair, not evidence that an already released writer remains active.

## Compute and supervision

Queue only the compute-constrained edge. Preserve fresh CPU/memory headroom;
keep one-minute load below roughly 1.5 times core count, available memory above
roughly 8 GiB, and avoid swap thrash. Run batch work at low scheduling priority.

Track every worker and background process with purpose, owner, expected progress
point, and reap action. Agent shell background work uses:

```text
run-bounded <duration> -- <command>
```

The duration cannot exceed 24 hours. On silence past the authorized window,
verify PID and cwd, stop the process, preserve evidence, then replace it only
with a narrower closer. Use round-unique line-anchored terminal markers. If the
user bus is unavailable, only an explicitly approved child-free diagnostic may
run under foreground `timeout`; that does not prove supervised product work.

## Terminal report and settlement

A worker reports attempt and role, exact artifact or capability gap, observed
gate source/result, unresolved findings or debt, actual lane/process/child
disposition, cleanup eligibility, wall/agent/queue/verification/review actuals,
and authoritative execution-observation provenance or explicit unknown.

The closure owner consumes that evidence, decides the product verdict and all
dispositions, updates continuity prose, and issues one `todo-distilled` SettlementCard.
A fresh `settle-work-distilled` clerk applies only the card's terminal fields, keyed
estimate receipt, and named lane state. After acknowledgement, the owner lands
and reaps through repository safety.
