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

## Supervise and stop

- Escalate only when the higher level can open a consequential action that the
  lower level cannot.
- Give each phase or case one accountable bound and surface progress inside it.
- On first failure or silence past the bound, stop the affected lane, reap its
  process tree, and preserve the available output and artifacts.
- Do not retry a failure into success, inflate a timeout, or turn remote CI
  into a landing gate. Classify infrastructure and timing failures as
  diagnostics until isolated.
- Do not continue checking after the named decision is made.
