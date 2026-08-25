---
name: todo-reference
description: >-
  Detailed todo continuity reference for record TOML, attempt and execution
  observations, SettlementCards, shape and dependency semantics, lifecycle
  updates, calibration receipts, and the acknowledged mailbox protocol. Use
  after todo-distilled routes here.
---

# Todo continuity reference

`todo-distilled` owns the boundaries and minimum workflow. This unit owns the
detailed schemas and protocols.

## Record schema

Use `<topic>-handoff-NN.md` for a continuation of one execution lane and a
stable descriptive filename for long-lived work. A record starts like this:

```toml
+++
id = "store-proposition-boundary"
title = "Separate proposition identity from assertion identity"
shape = "project"
life = "active"
updated_at = "2026-08-14T11:36:50+08:00"
owners = ["codex:/root"]
requires = []
conversation_ids = ["codex:019ffd07-c27b-7943-8a66-553dff2ae98b"]
coordination = ["agent-coord.md#C007"]

[[lane]]
repo = "beagle"
worktree = "~/code/beagle/worktrees/store-proposition-boundary"
branch = "store-proposition-boundary"
owner = "codex:/root"
state = "active"
+++
```

Follow the front matter with `Outcome`, `Current state`, `Decisions`, `Next
actions`, `Verification`, and `Recovery and cleanup`. Required root fields are
`id`, `title`, `shape`, `life`, `updated_at`, and `owners`. Add dependency,
conversation, coordination, and lane fields when they exist. Conversation IDs
are provider/session identifiers recoverable with `convo session <uuid>`.

## Attempt and terminal receipt

An executing task or project starts one forecast/staffing join:

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

At settlement add `ended_at`, `outcome`, `wall_time_actual`,
`agent_time_actual`, `queue_block_time_actual`, `verification_time_actual`,
`execution_observation`, review fields, and race fields when applicable.
Durations are compact values; elapsed wall time is the critical path, agent
time is summed execution, and queue/verification/review-repair measurements
explain overlapping portions rather than values to add. Store causal prose in
the corresponding cause/summary field.

Write one keyed terminal receipt to
`~/code/todo/estimate-calibration.md` with the shared estimate/actual, route,
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

## SettlementCard

The immutable card carries schema `agent-settlement-card/v1`, exact record path
and SHA-256, record and authorizer identity, issue time, commit, verdict and
evidence arrays, debt, terminal attempt delta, and exact lane state. Its
`[attempt]` table adds terminal fields only; it does not restate forecast or
staffing. Evidence entries use `<exact source> :: <observed result>`.

The validator checks record hash and identity, authorization, chronology,
verdict/evidence consistency, review, debt, lane identity, duration relations,
observation schema, units, hashed joins, count safety, and segment coalescing.
Every supplied terminal field must be absent or already equal in the record.
Require `ended_at - started_at == wall_time_actual` at compact-duration
precision; each explanatory duration must not exceed wall time.

Attempt fields, attempt-owned debt, and lane state are one atomic todo-record
replacement. The deterministic keyed estimate receipt follows as a separate
atomic update. Therefore replay may observe the original record, the complete
record replacement without its receipt, or both complete targets. A stale
digest is acceptable only when the todo target is already exact and only the
receipt remains.

## Shapes, links, and debt

- `thread`: continuity matters.
- `plan-draft`: action/outcome/value story is being formed.
- `proposal`: a plan-draft offered for adoption.
- `plan`: a solidified journey whose value is asserted.
- `project`: a plan whose execution has started.
- `task`: a delegated action realizing a tracked plan/project.
- `resource`: a useful person, work, service, or agent.

Tasks add `realizes`, `assigned_to`, and `delegated_by`. `requires` stores the
dependent-to-prerequisite direction; derive reverse and currently unsatisfied
views. Internal links use exact record IDs; external prerequisites use the
`external:` prefix. A project uses `plan` only for a distinct tracked plan.

Track a consciously deferred gap with `[[quality_debt]]` fields `attempt`,
`path`, `invariant`, `severity`, `owner`, and `exit_condition`. Remove the debt
when its exit condition is proven.

## Mailbox protocol

One named monitor must watch `agent-coord.md`, deliver changes to its owner
within a bound, and be reaped with its supervisor. Prove the route with one
addressed round trip:

```text
- [timestamp][C007][sender -> receiver][OPEN] request or claim
- [timestamp][C007][receiver -> sender][ACK] received and accepted/declined
- [timestamp][C007][sender -> receiver][UPDATE] changed checkpoint
- [timestamp][C007][sender -> receiver][DONE] terminal result and revision
```

Messages remain append-only while a claim is live. On a delivery timeout,
append one explicit retry and retain ownership. Before stopping the monitor,
reread the board and settle every addressed `OPEN` and `UPDATE`.
