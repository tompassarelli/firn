# Attempts and execution observations

## Attempt identity

An attempt joins one resumable execution's forecast, observed work, and terminal
result. It is not a second owner or a reason to start staffing/calibration.
Unknown evidence must remain unknown; exact-looking invented fields damage
future estimates.

## Attempt and terminal receipt

When a resumable execution record is independently required, give it one
attempt. The following expanded example includes optional forecast/staffing
facts; include them only when actually needed and observed:

```toml
[[attempt]]
id = "A1"
seam = "one independently verifiable outcome"
class = "compiler-one-seam"
wall_time_estimate = "8m"
agent_time_estimate = "8m"
calibration_sample_count = 3
started_at = "2026-08-23T16:15:34+08:00"
model = "gpt-5.6-terra"
reasoning = "high"
route = "north:standard/high"
assignment_id = "north-assignment-id-or-none"
role = "worker"
review_budget = "owner"
```

`model` and `reviewer_model` name the concrete runtime model. They never use a
lineage, ambient, or selection placeholder; recover the exact identity from
run or dispatch evidence rather than guessing, and record any evidence gap
outside those fields.

At settlement add `ended_at`, `outcome`, `wall_time_actual`,
`agent_time_actual`, `queue_block_time_actual`, `verification_time_actual`,
`execution_observation`, review fields, and race fields when applicable.
Durations are compact values; elapsed wall time is the critical path, agent
time is summed execution, and queue/verification/review-repair measurements
explain overlapping portions rather than values to add. Store causal prose in
the corresponding cause/summary field.

When that attempt participates in durable estimate calibration, write one
keyed terminal receipt to `~/code/todo/estimate-calibration.md` with the shared estimate/actual, route,
staffing, outcome, and concise overrun facts. Ratios remain derivable. Provider
cost or token actuals appear only when an authoritative source supplies them.

## Execution observation v1

An exact `agent-execution-observation/v1` object uses:

- `coverage = "exact"`;
- lowercase source tokens;
- units `assistant-turn` and `admitted-tool-call`;
- hashed provider/attempt/session evidence;
- ordered segments with `mode`, positive `turn_count`, non-negative
  `tool_call_count`, and unique lowercase SHA-256 turn identities.

Counts and derived totals must not exceed 9,007,199,254,740,991. Coalesce
adjacent equal modes while preserving non-adjacent recurrence. Exact coverage
requires a settings snapshot before every counted turn and an exact join to the
latest preceding snapshot. Codex `priority` maps to `fast`; explicit `default`
maps to `standard`.

When initial mode, exact joins, comparable units, or complete coverage is
absent, use `coverage = "unknown"`, one stable source/reason, unknown units,
empty evidence, and no segments. Do not retain partial counts, infer a mode
from silence, fabricate zeroes, or store raw identifiers, paths, transcript
text, prompts, tool arguments, or results.

## Terminal replacement

The product owner fixes terminal evidence and applies the complete terminal
attempt fields, attempt-owned debt, and lane state as one atomic todo-record
replacement. Preserve forecast fields and ordered execution-observation
segments. Require `ended_at - started_at == wall_time_actual` at compact-duration
precision; each explanatory duration must not exceed wall time.

If calibration applies, write the deterministic keyed estimate receipt as a separate atomic update,
then re-read both targets. Replay may observe the original record, the complete
record replacement without its receipt, or both complete targets; partial
terminal fields, debt, or lane mutation are invalid.

The two-file update has an explicit recoverable midpoint: the terminal record
may exist before its receipt. Idempotent keyed replay finishes that midpoint
without duplicating history. It must not observe half-written terminal fields.
