---
name: smoke
description: >-
  Use whenever selecting, proposing, running, supervising, escalating, or
  interpreting a smoke check, focused test, integration check, full journey,
  release preflight, or CI result. Chooses the lowest bounded evidence that can
  change the next decision and classifies checks from seam through publishing.
---

# smoke — checks that change a decision

Treat a check as a decision instrument. Run the lowest deterministic layer
that can prove the claim; stop when its result decides the next action.

Freeze acceptance criteria when delivery starts. A new reproducible product
failure may block, but an observation does not silently create a new guarantee.
For reversible work, keep unplanned diagnosis within one fifth of the expected
delivery window unless security, data integrity, an irreversible migration, or
a published contract is at risk.

## Declare the run

Before starting, state these five fields in one compact block:

```text
Claim: <what this run can prove>
Decision: <what pass or fail changes next>
Level: <L0, L1, L2, or L3>
Bound: <deadline and visible progress point>
Supervisor: <actor that owns and reaps every child>
```

Do not run the check when pass and fail lead to the same next decision.

## Choose the level

| Level | Evidence | Default bound | Use only when |
| --- | --- | --- | --- |
| L0 | One seam, pure rule, parser, formatter, or static fact | 10 seconds | Its result can decide the immediate edit or handoff |
| L1 | One controlled integration boundary | 30 seconds | L0 cannot prove the owned interaction |
| L2 | One critical full journey | 2–3 minutes | Success opens a consequential cutover or landing action |
| L3 | Exact-commit local release gate | Repository bound, never open-ended | Publishing a final tag or shipped artifact is the next action |

A compiler-wide full smoke is L2. Defer it while lower-level module/default
behavior or obligation failures already block the cutover.

## Design deterministic evidence

Put each claim at the lowest layer that proves it. Keep unrelated concerns in
separate checks; do not ask one journey to prove networking, persistence,
rendering, performance, and external availability at once. Control owned
clocks, randomness, state, versions, and dependencies where they affect the
verdict. Keep public networks, wall-clock timing, schedulers, GPUs, and shared
services out of correctness gates.

Test owned behavior and integration boundaries, not dependency internals or
platform conformance already owned upstream. Hermeticity is a means, not the
goal: do not build a harness or broaden a probe unless its absence changes the
shipping decision.

## Batch expensive checks

Make every independent edit that can be reasoned about before paying for a slow
build or gate. Serialize only when a later edit is meaningless unless an
earlier result passes. Cheap seam checks may run throughout the edit loop; a
slow check runs once for the batch, not for reassurance or intermediate
progress.

Mine a slow failure as one inventory: preserve all reported failures, group
them by cause, repair the causes, then run the gate once more. Do not rediscover
one symptom per slow run. Report the number of slow verification runs consumed.

Routine verification must fit its recorded two-to-three-minute bound. Treat a
slower loop as a verification defect; improve its architecture rather than
silently extending the timeout.

## Classify gates and releases

A release gate must be named before release, reproducible, attributable to the
product, and capable of changing the shipping decision. Infrastructure,
timing, and probe failures remain diagnostic until isolated. Never retry a gate
failure into success; keep diagnostic retries visible and demote a flaky gate
until repaired. Give ambiguity one bounded diagnostic pass.

Local supervised checks decide repository landings. Remote CI is asynchronous
confirmation and never a landing gate. It may gate only publication of the
artifact it produces.

Before publishing a final SemVer tag, require the repository's non-publishing
release gate to pass for the exact commit the tag names. A failed candidate
consumes no final version: repair it and retry the same version. Do not publish
a later final version while an earlier public final tag lacks a successful
release for its exact commit. Moving, deleting, or recreating a published final
tag requires the applicable operator authority and must preserve one
chronological tag-to-release mapping.

## Supervise and stop

- Escalate only when the higher level can open a consequential action that the
  lower level cannot.
- Give each phase or case one accountable bound and surface progress inside it.
- Do not use one whole-suite timeout in place of phase or case deadlines.
- On first failure or silence past the bound, stop the affected lane, reap its
  process tree, and preserve the available output and artifacts.
- Do not retry a failure into success, inflate a timeout, or turn remote CI
  into a landing gate. Classify infrastructure and timing failures as
  diagnostics until isolated.
- Do not continue checking after the named decision is made.
