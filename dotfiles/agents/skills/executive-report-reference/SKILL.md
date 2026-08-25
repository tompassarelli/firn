---
name: executive-report-reference
description: >-
  Report-type, source-scope, disposition, reporting-unit, and composition
  reference for executive-report-distilled. Load only when that skill routes
  here through `agents path executive-report-reference`; this is not the trigger
  or minimum workflow for producing an executive report.
---

# Executive report reference

The distilled skill owns source authority, the four-format decision, completion
threshold, and minimum report composition.

## Source scope by report

- Executive Report and Weekly Review source every substantive workstream,
  collapsing only fronts with no material state or portfolio consequence.
- Workstream Brief sources the named commander.
- Milestone Retrospective sources the commander or commanders that owned the
  milestone and its consequential dependencies.

The canonical current card schema comes from executive orchestration. A
report-scoped commander synthesis may add goal and value, window delta, or the
minimum material history absent from that card; it does not establish a second
state-card schema.

## Four report types

| Type | Horizon and purpose | Shape |
| --- | --- | --- |
| Executive Report | Roughly the last 12–24 hours; current operational view | What changed, what matters now, and what happens next across a few active fronts |
| Weekly Review | Roughly the last 5–7 days; trajectory | Major progress, setbacks, strategy changes, and workstream evolution, synthesized rather than concatenated from daily reports |
| Workstream Brief | Current, effectively timeless reacquisition | Purpose, value, goal, current state, only the history needed to understand it, blockers, and next frontier |
| Milestone Retrospective | Occasional history for consequential closure | How the significant milestone happened and what it unlocks |

No additional dashboard, digest, project-update, or reporting taxonomy is
needed.

## Reporting unit detail

Within **Goal → What changed → Current state → Next**:

- Goal states the outcome and its value rather than a task label.
- What changed states only deltas in the report horizon that alter the outlook.
- Current state identifies disposition, authority stage, exact artifact or
  milestone, and the evidence supporting that stage.
- Next identifies the next outcome, true prerequisites, closure order, and only
  forecast variance that changes expectations.

Disposition meanings:

- `active`: owned work is progressing now;
- `held`: an exact unmet dependency prevents progress;
- `parked`: priority has consciously deferred the front;
- `completed`: the promised target-authority artifact, decisive gate, and
  settlement are all present.

A stale flag, dirty lane, candidate branch, or worker confidence does not
establish one of these states.

## Composition detail

An Executive Report or Weekly Review begins with direction of travel, the
current critical-path controller, and its most important consequence. It then
orders workstreams by value and closure dependency. Portfolio synthesis can add
the true cross-workstream closure order, resource or topology health, operator
decisions, and verdict-changing uncertainty.

A Workstream Brief begins with purpose and present verdict. A Milestone
Retrospective begins with consequential closure. These focused formats include
only relevant dependencies, decisions, and uncertainty rather than collecting
portfolio-wide state.

Direct prose and uneven section weight preserve executive signal better than a
uniform activity table when workstreams differ materially in importance.
