---
name: agent-runtime-incident-distilled
description: >-
  Investigate and close unexplained agent admission, startup, death, liveness, control, or reporting failures at their owning cause.
---

# Agent-runtime incidents

Delivery completion does not close a reliability incident. Preserve the intended
and emitted operation, normalized error, runtime mode, affected boundary, and
bounded evidence before a retry changes it. Exclude credentials and unrelated
transcript content.

Create or join one `IncidentSeed` by its stable signature; run IDs and
timestamps do not distinguish causes. Keep delivery state, containment, and
repair evidence separate. Use the existing authorized continuity record.

State a falsifiable hypothesis and run the smallest safe reproduction.
Classify the lifecycle and supported cause, then assign the exact upstream
owner. A fallback does not repair the incident or gain authorization here.

Follow the current-generation sequence:
`seeded → contained → investigated → classified → owned → repaired →
regressed → activated → primary-canaried → closed`.
Blocked reproduction remains open. Recurrence increments the generation and
requires fresh repair, activation, primary-path, and restoration evidence.

Close only after the owning repair lands, its regression passes, the repaired
authority is active, and the original triggering path works with the preferred
topology restored. North owns run settlement and any fallback restoration debt.

Full notes: [seeding and deduplication](references/seeding.md),
[containment and diagnosis](references/diagnosis.md), and
[repair, upstream reporting, and closure](references/closure.md).
