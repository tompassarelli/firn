---
name: agent-runtime-incident
description: >-
  Investigate and close unexplained agent admission, startup, death, liveness, control, or reporting failures at their owning cause.
grounded: 2026-10-09
written: 2026-10-09
---

# Agent runtime incidents

- Capture intended/emitted operation, error, runtime mode and relevant evidence before retrying.
- Join one IncidentSeed by stable cause signature and keep delivery, containment and repair evidence separate.
- Use the existing authorized continuity record and exclude credentials/unrelated transcripts.
- Reproduce one supported hypothesis, classify the lifecycle/cause and assign the upstream owner.
- Follow `seeded → contained → investigated → classified → owned → repaired → regressed → activated → primary-canaried → closed`.
- Keep blocked reproductions open and increment recurrence generations for fresh repair/activation/primary-path/restoration evidence.
- Close after the repair lands, regression passes, activation takes effect and the original path works with preferred topology restored.
- Let North settle runs and fallback restoration debt.

Use [seeding](references/seeding.md), [diagnosis](references/diagnosis.md) or [closure](references/closure.md) for a named unresolved detail.
