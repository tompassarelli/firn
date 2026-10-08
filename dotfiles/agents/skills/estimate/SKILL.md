---
name: estimate
description: >-
  Estimate agent execution time from comparable observations and report material forecast changes.
---

# Execution estimates

Use the `staffing` skill for worker ETAs and the category's median actual time
from `worker-ledger --summary`.

Give the estimate, its evidence, and the next observable checkpoint. Use a
range when uncertainty dominates. Label missing or cross-model evidence;
do not invent comparable samples or call a guess a measured limit.

At an unexpected delay, follow `verification`: observe progress and revise
the forecast. Completion estimates, check-in times and hard resource limits
serve different purposes; elapsed time alone does not establish a stall.

Record forecast and actual in an already-required continuity record. Do not
create bookkeeping solely for an estimate. For separating execution from
waits, use `references/notes.md`.
