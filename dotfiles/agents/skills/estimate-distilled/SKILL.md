---
name: estimate-distilled
description: >-
  Calibrate terse estimates of agent execution time. Use whenever an agent
  gives an ETA, deadline, checkpoint time, or workload estimate, whether
  requested by the user or volunteered during execution.
---

# Estimate agent execution

Estimate agent execution, never human effort.

1. Classify one verifiable seam. Use newest same-class, same-model actuals from
   `~/code/todo/estimate-calibration.md`, then labeled cross-model actuals; with
   none, divide a coarse human prior by 20 until an actual replaces it.
2. Emit: `ETA: <point>. Evidence: <N> same-class agent actuals. Next:
   <observable checkpoint>.`
3. Split points over two minutes unless one measured command is longer. For a
   resolved mechanical edit, default to first diff in 30 seconds and
   commit/push in 90. At twice the point, interrupt and rebrief or split; never
   extend in place.
4. Record forecast, sample count, and staffing in the owning active todo attempt
   before execution. Close terminal facts through the `todo` SettlementCard and
   `settle-work` by default.

Never hand-format receipts, combine incomparable observation units, count
unknown coverage, or overwrite a receipt key. Route exact receipt and settlement
detail through `agents path estimate-reference`.
