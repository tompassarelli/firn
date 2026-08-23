---
name: executive-report
description: >-
  Turn current commander state cards into direct, outcome-first portfolio
  reporting. Use whenever the operator asks for an “executive report,” asks to
  keep tabs on everything across current workstreams, or requests a “weekly
  review,” “workstream brief,” or “milestone retrospective” of current
  commander-owned work. Default an unqualified current portfolio report to
  Executive Report: the operational view over roughly the last 12–24 hours. Do
  not use this skill merely to run, staff, or delegate the workstreams.
---

# Executive report

Compress authoritative workstream state into what the operator needs to
understand and decide. Preserve the important differences between fronts;
remove the tracking exhaust.

## Build from commander state

Select the source scope before collecting state:

- For Executive Report and Weekly Review, source every substantive workstream.
- For Workstream Brief, source the named workstream.
- For Milestone Retrospective, source only the commander or commanders that
  owned the milestone and its consequential dependencies.

Require every selected commander to replace its canonical current compact state
card as defined by executive orchestration. Do not define a second card schema.
When the report needs goal/value, a report-window delta, or material history
that is absent from the current card, ask that commander for a compact
report-scoped synthesis. Obtain both through commanders rather than inspecting
repositories, todo files, or leaf output at root.

Treat a missing or conflicting current card as uncertainty; do not silently
reconstruct certainty from raw inspection. Executive Report and Weekly Review
cover every substantive workstream, but may collapse fronts with no material
state or portfolio consequence.

## Select one of four report types

Use no reporting taxonomy beyond these four:

1. **Executive Report — today.** This is the default operational view over
   roughly the last 12–24 hours: what changed, what matters now, and what
   happens next. Organize it around a few active workstreams, not around agents,
   commits, or a chronological activity feed.
2. **Weekly Review — trajectory.** Cover roughly the last 5–7 days. Explain
   major progress, setbacks, strategy changes, and how workstreams evolved.
   Synthesize the trajectory; never concatenate daily or executive reports.
3. **Workstream Brief — context.** Give a current, effectively timeless
   reacquisition of one workstream: what it is, why it matters, its goal,
   current state, only the major history needed to understand that state,
   blockers, and the next frontier.
4. **Milestone Retrospective — history worth preserving.** Use this
   occasionally, only for genuinely significant closure. Explain how the
   milestone happened and what it unlocks. A trivial completion remains a
   workstream line item or is omitted; it does not earn a retrospective. If
   asked for one anyway, decline the form plainly and give at most a one-line
   closure result.

When the request names a type, use it, except that a trivial closure still does
not meet the retrospective threshold. When it asks for the current portfolio
without naming one, use Executive Report. Do not invent daily digests, project
updates, dashboards, or other report types.

## Use one reporting unit

For every included workstream, preserve this semantic order:

**Goal → What changed → Current state → Next**

Keep the unit compact, but include enough exact detail to understand the front:

- **Goal:** state the outcome and its value, not the task label.
- **What changed:** name the material delta within this report's time horizon.
  Omit activity that did not change the outlook.
- **Current state:** distinguish the disposition and authority stage. Name the
  exact artifact or milestone and the evidence that makes the stage true.
- **Next:** name the next outcome, its true prerequisites, and where it sits in
  closure order. Surface forecast variance only when it changes expectations.

Use active for owned work progressing now; held for an exact unmet dependency;
parked for a conscious priority choice; and completed only when the promised
artifact has reached the objective's target authority stage and its decisive
gate and settlement are present. A stale todo flag, dirty lane, candidate
branch, or confident worker claim does not establish any of these.

## Compose the report

Lead Executive Report and Weekly Review with a candid portfolio verdict:
direction of travel, what now controls the critical path, and the most important
consequence. Then order workstreams by portfolio value and closure dependency
rather than giving each equal weight. Lead a Workstream Brief with its purpose
and current verdict; lead a Milestone Retrospective with the consequential
closure.

For Executive Report and Weekly Review, include only the portfolio synthesis
that is material:

- critical path and closure order, including true cross-workstream
  dependencies;
- resource and topology health, such as an unowned ready front, a silent
  commander, avoidable serialization, or constrained capacity;
- decisions required from the operator, with a recommendation first and
  alternatives only when a real decision exists;
- residual uncertainty that could change the verdict.

For Workstream Brief and Milestone Retrospective, include only the relevant
dependency, decision, and uncertainty; do not collect portfolio-wide state.

Say plainly when no operator decision is required. Distinguish observed
evidence from inference, and state an unknown instead of manufacturing
confidence.

## Keep executive signal

Write direct, outcome-first prose. Prefer a small number of informative
paragraphs or workstream sections over a uniform table when importance differs.
Do not emit raw leaf logs, worker-by-worker narration, chronology dumps,
internal task lists, stale todo flags, repaired-finding history, or an
equal-weight laundry list. Do not call a candidate “done,” a commit
“published,” a publication “activated,” or an activation “proven live.”
