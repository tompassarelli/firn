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
joins exactly one durable `IncidentSeed`. Delivery may continue through
quarantine, replacement, or an already-authorized fallback, but delivery
completion never closes the incident.

## Seed and deduplicate

Before a retry or replacement changes the evidence, preserve intended
operation, emitted recipient/tool and argument shape, exact error or terminal
signal, runtime/provider mode, actor/run identity, time, correction history,
and the affected seam. Store bounded evidence or exact references; exclude
credentials and unrelated transcript content.

Create or join one `IncidentSeed` in the current authorized durable
continuity record with:

- `signature`, `generation`, `state`, `lifecycle_class`, `cause_class`, and
  stable affected seam or surface scope;
- intended and emitted operations, normalized argument shape, runtime mode,
  error class, first/last observation, count, and preservation evidence;
- containment, delivery state, hypotheses, one reproduction, and upstream owner;
- repair, regression, activation, primary-canary, and restoration-debt evidence.

Derive the stable signature from the canonical tuple
`(lifecycle class, stable affected actor or sender role, intended operation or
report boundary, emitted recipient/tool or payload surface, normalized
argument or payload signature, runtime/provider mode, error class, stable
affected seam/surface scope)`. Exclude timestamps, run-specific actor and
opaque IDs, and secret or volatile values. Normalize scope to the smallest
stable, non-run-specific seam or surface. If one observation spans multiple
scopes, split it deterministically and create or join one seed per scope;
never deduplicate across scopes.

A complete tuple match updates last observation, count, and evidence instead
of creating another seed, including a retry with a new run identity. A changed
tuple is a new signature until evidence proves otherwise. For reporting or
control payload failures, retain a normalized envelope/error signature rather
than the opaque payload itself.

## Contain and investigate

Quarantine only the defective call, run, or lifecycle seam. Continue a
replacement only after Agent Machinery supplies a fresh portable run design and
North admits it through `agent-run-lifecycle-distilled`; keep independent work
moving. North may fall back only with typed proof that no provider side effect
became observable. Preserve requested and resolved route evidence and any
restoration debt. If that proof is unavailable, do not retry or switch runtime;
record the blocked delivery state. This incident workflow never admits fallback.
Preserve delivery containment separately from incident state.

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

This skill alone owns incident lifecycle transitions and the reliability
closure decision. `agent-run-lifecycle-distilled` owns concrete fallback,
restoration, and terminal agent-run settlement. Record its route and
restoration-debt facts as incident evidence without creating a second debt
model, broadening fallback authority, or changing the default. Fallback
completion may close delivery containment but not the incident.

Use explicit states:
`seeded → contained → investigated → classified → owned → repaired → regressed
→ activated → primary-canaried → closed`. `reproduction-blocked` and
`reopened` remain open. Do not skip a state without its named evidence.

When a closed signature recurs, increment `generation`, enter `reopened`, and
retain prior evidence as history tagged with its old generation. Old repair,
regression, activation, primary-canary, and restoration-debt exit evidence is
stale for the new generation and cannot satisfy closure. From `reopened`, make
a fresh transition through containment, investigation, classification,
ownership, repair, regression, activation, and primary canary before closing;
do not close directly from `reopened` or reuse old-generation evidence.

Close only when the upstream repair is landed, the focused regression passes,
the repaired authority is activated, the preferred topology is restored, and
a primary-path canary exercises the triggering lifecycle seam successfully,
all in the current generation. When current-generation fallback restoration
debt exists, also require its North-owned exit evidence. Fallback-path
success is not a primary canary.
