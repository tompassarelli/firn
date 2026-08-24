---
name: estimate
description: >-
  Calibrate terse estimates of agent execution time. Use whenever an agent
  gives an ETA, deadline, checkpoint time, or workload estimate, whether
  requested by the user or volunteered during execution.
---

# Estimate agent execution

Estimate the agent's execution, never a human's effort.

## Form the estimate

1. Classify the independently verifiable seam being estimated.
2. Read `~/code/todo/estimate-calibration.md` and anchor to the most recent
   same-class, same-model agent actuals. If that sample is too small, use the
   same-class cross-model actuals and label the sample scope. State how many
   matching samples support the point.
3. When no matching agent observation exists, use a coarse human prior divided
   by 20. Replace that prior immediately when an observed agent timing exists.
4. Emit exactly one point ETA, the evidence sample count, and the next
   observable checkpoint. Avoid comfort ranges and precision unsupported by
   the samples.

Use this terse shape:

```text
ETA: <point>. Evidence: <N> same-class agent actuals. Next: <observable checkpoint>.
```

If a calendar deadline is required, derive it from the point ETA and still name
the execution duration. Treat a workload estimate the same way: classify its
seams and report when the next result becomes observable.

## Bound execution

- Decompose any estimate over two minutes into independently observable seams,
  unless one measured command itself takes longer. Name that command and its
  observed duration.
- For a resolved mechanical edit with no contrary observations, default to a
  first-diff checkpoint within 30 seconds and commit/push within 90 seconds.
- At twice the point estimate, interrupt and rebrief the work or split the seam.
  Do not extend the estimate in place.

## Close the loop

Before execution, create the `[[attempt]]` in the owning active todo record
with its point forecast, sample count, and selected staffing; add only a terse
in-flight pointer to the flat restart-grade ledger at
`~/code/todo/estimate-calibration.md`. Every execution record gets this
forecast before work begins, including a solo owner; inactive proposals and
resources do not fabricate one.

After every completion, the product owner fixes the exact terminal facts. At a
terminal worker boundary, delegate their mechanical copy through the `todo`
SettlementCard and `settle-work` by default. Settle directly only when no
admitted worker slot exists or dispatch costs more than this bounded update.

Replace the in-flight pointer with one completed receipt: wall and agent time
estimates and actuals, queue/block and verification time actuals, the derived
wall-time actual-to-estimate ratio, selected model/reasoning/route/role, race
result where relevant, and concise overrun cause or `none`. Include exact commit
review findings, review-repair time actual, and explicitly deferred quality
debt when they exist. A settler copies these values from the owner-issued card
and owning attempt; it never estimates a missing actual or upgrades a verdict.
The `todo` skill owns the shared field and card contracts. Refresh same-class
calibration from settled receipts; use model-specific observations when enough
exist, and otherwise retain the labeled cross-model fallback. Keep the ledger
as concise Markdown with TOML front matter; it is a learning record, not a
second live-work tracker.
