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

Replace the in-flight pointer with one deterministic completed receipt keyed by
`<record_id>/<attempt_id>`. Render fields in this order: ended-at, seam, class,
wall estimate/actual, agent estimate/actual, queue/block actual, verification
actual, model, reasoning, route, role, assignment ID, outcome, overrun cause,
race outcome, reviewed commit/outcome/summary, reviewer model/reasoning, review
repair actual, canonical execution-observation JSON, and exact quality-debt
entries. Copy values from the validated card and owning attempt; preserve
execution segment array order while sorting object keys for the canonical JSON.
Render an absent optional value as `none`, and use
`none` when the optional card overrun cause is absent. Do not paraphrase a
value, add provider actuals, or serialize the derivable wall-time ratio. Reject
CR or LF in every text value rendered directly into the receipt line; canonical
JSON escaping remains authoritative for structured observation and debt values.

Use exact execution observations for calibration only within the same source,
`assistant-turn` unit, and `admitted-tool-call` unit. Keep `coverage =
"unknown"` observations explicit but out of count- or mode-based cohorts.
Never merge provider-turn or provider-tool-item facts into these comparable
units, and never derive a zero or standard-mode sample from unknown coverage.

The stable key may occur only once. An identical receipt is an idempotent
replay; a different receipt with that key is a conflict. The settler never
rewrites another receipt or authors calibration prose. Render with the
SettlementCard validator's `--render-receipt` path and apply with the atomic
keyed updater owned by `settle-work`; do not hand-format the line. The `todo` skill owns
the shared field and card contracts. Refresh same-class calibration from
settled receipts; use model-specific observations when enough exist, and
otherwise retain the labeled cross-model fallback. Keep the ledger as concise
Markdown with TOML front matter; it is a learning record, not a second
live-work tracker.
