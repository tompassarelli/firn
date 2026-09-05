---
name: estimate-distilled
description: >-
  Estimate agent execution time from comparable observations and report material forecast changes.
---

# Execution estimates

Estimate agent execution, not human effort. Prefer recent same-task-class,
same-model actuals from `~/code/todo/estimate-calibration.md`; label
cross-model evidence or an uncalibrated prior explicitly.

Give the estimate, its evidence, and the next observable checkpoint. Use a
range when uncertainty dominates. Do not present a guessed duration as a
measured limit or invent comparable samples.

At an unexpected delay, follow `verification-distilled`: observe progress and
revise the forecast without automatically killing useful work. Completion
estimates, check-in times, and hard resource limits serve different purposes.

Record forecast and actual in an already-required continuity record; do not
create bookkeeping solely for an estimate. Keep observation units comparable,
unknown coverage explicit, and receipt keys unique. For receipt fields and
calibration semantics, use `agents path estimate-reference`.
