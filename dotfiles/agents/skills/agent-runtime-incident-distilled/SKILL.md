---
name: agent-runtime-incident-distilled
description: >-
  Investigate, deduplicate, contain, repair, activate, and close agent-runtime
  reliability incidents. Use for unexplained agent admission, startup, death,
  silence or liveness, collaboration-control, or terminal-reporting behavior,
  including delivery that uses quarantine, replacement, or fallback after such
  an anomaly.
---

# Agent-runtime incident lifecycle

## Incident invariant

Treat delivery and reliability as independent lifecycles. An unexplained
admission, startup, death, liveness, control, or reporting anomaly seeds or
joins exactly one durable `IncidentSeed` while quarantine, replacement, or
fallback keeps delivery moving. Delivery completion never closes the incident.

## Seed and deduplicate

Before a retry or replacement changes the evidence, preserve intended
operation, emitted recipient/tool and argument shape, exact error or terminal
signal, runtime/provider mode, actor/run identity, time, correction history,
and the affected seam. Store bounded evidence or exact references; exclude
credentials and unrelated transcript content.

Create or join one `IncidentSeed` in the current authorized durable
continuity record with:

- `signature`, `state`, `lifecycle_class`, `cause_class`, and affected seam;
- intended and emitted operations, normalized argument shape, runtime mode,
  error class, first/last observation, count, and preservation evidence;
- containment, delivery state, hypotheses, one reproduction, and upstream owner;
- repair, regression, activation, primary-canary, and restoration-debt evidence.

Derive the stable signature from the canonical tuple
`(lifecycle class, intended operation, emitted recipient/tool, normalized
argument shape, runtime/provider mode, error class)`. Exclude timestamps,
run-specific opaque IDs, and secret or volatile values. A complete match
updates last observation, count, and evidence instead of creating another
seed; a recurrence reopens a closed match. A changed tuple is a new signature
until evidence proves otherwise.

## Contain and investigate

Quarantine only the defective call, run, or lifecycle seam. Admit replacement
or bounded fallback in parallel and keep independent work moving. Preserve
delivery containment separately from incident state.

Write falsifiable hypotheses before naming a cause: each states its predicted
observation and what would refute it. Run one smallest safe, authorized,
bounded reproduction after pricing it, with the expected signal declared in
advance. Do not blind-retry; if no such reproduction is available, record
`reproduction-blocked` and keep the incident open.

Classify the lifecycle seam as `admission`, `startup`, `death`,
`liveness`, `control`, or `reporting`, and the supported cause as
`invocation`, `worker`, `provider-runtime`, `policy`, `external`, or
`unknown`. Assign the exact upstream source or runtime owner; a fallback is
never the upstream owner.

## Restoration and closure

`executive-orchestration-distilled` alone admits and governs fallback
restoration debt. Carry that debt as incident evidence without creating a
second debt model, broadening fallback authority, or changing the default.
Fallback completion may close delivery containment but not the debt or
incident.

Use explicit states:
`seeded → contained → reproduced → classified → owned → repaired → regressed
→ activated → primary-canaried → closed`. `reproduction-blocked` and
`reopened` remain open. Do not skip a state without its named evidence.

Close only when the upstream repair is landed, the focused regression passes,
the repaired authority is activated, the preferred topology is restored, and
a primary-path canary exercises the triggering lifecycle seam successfully.
Fallback-path success is not a primary canary.
