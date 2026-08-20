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
   same-class agent actuals. State how many matching samples support the point.
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

Before execution, add the prediction and start time to the flat restart-grade
ledger at `~/code/todo/estimate-calibration.md`. After every completion, move
it to the completed observations with the actual elapsed time, ratio, and a
concise overrun cause or `none`; then refresh the same-class calibration. Keep
the ledger as concise Markdown with TOML front matter, following the `todo`
skill's storage contract.
