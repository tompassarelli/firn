---
name: todo-reference
description: >-
  Detailed todo continuity reference for record TOML, attempt and execution
  observations, shape and dependency semantics, lifecycle updates, calibration
  receipts, and the acknowledged mailbox protocol. Use after todo-distilled
  routes here.
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

## Terminal record update

The product owner fixes terminal evidence and applies the complete terminal
attempt fields, attempt-owned debt, and lane state as one atomic todo-record
replacement. Preserve forecast fields and ordered execution-observation
segments. Require `ended_at - started_at == wall_time_actual` at compact-duration
precision; each explanatory duration must not exceed wall time.

Write the deterministic keyed estimate receipt as a separate atomic update,
then re-read both targets. Replay may observe the original record, the complete
record replacement without its receipt, or both complete targets; partial
terminal fields, debt, or lane mutation are invalid.

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
- [timestamp][C007][sender -> receiver][OPEN] event=EVENT proof=TOKEN request or claim
- [timestamp][C007][receiver -> sender][ACK] event=EVENT proof=TOKEN received and accepted/declined
- [timestamp][C007][receiver -> sender][PING] event=EVENT proof=TOKEN liveness receipt
- [timestamp][C007][sender -> receiver][UPDATE] event=EVENT changed checkpoint
- [timestamp][C007][sender -> receiver][DONE] event=EVENT terminal result and revision
```

Messages remain append-only while a claim is live. On a delivery timeout,
append one explicit retry and retain ownership. Before stopping the monitor,
reread the board and settle every addressed `OPEN` and `UPDATE`.

### Executable bootstrap

Resolve the helper from active authority, never from a projection or remembered
path:

```bash
todo_skill=$(dirname "$(agents path todo-distilled)")
mailbox_helper="$todo_skill/scripts/cross-supervisor-mailbox.mjs"
```

The initiating monitor publishes and arms in one invocation. `--sender` is the
local root, `--receiver` is the exact peer root, and `--status` is the expected
peer response:

```bash
bun "$mailbox_helper" open-watch \
  --mailbox ~/code/todo/agent-coord.md \
  --coordination C007 \
  --sender "codex:/root" \
  --receiver "peer:/root" \
  --status ACK \
  --timeout-ms 60000 \
  --message "acknowledge the shared concern"
```

The helper creates the event ID, UTC timestamp, and proof token. A caller may
supply `--proof TOKEN` only for an already-created fresh request; ordinary
bootstrap omits it. `OPENED` and `ARMED` are diagnostics on stderr. Stdout stays
empty until the first new exact peer line, then contains that one line only and
the process exits zero. Timeout exits 124; argument, watch, or read failure
exits 2. The timeout must remain at or below 300000 milliseconds.

The peer responds without hand-writing mailbox syntax. It copies the proof from
the addressed `OPEN`; the helper supplies its own new event ID and timestamp:

```bash
bun "$mailbox_helper" reply \
  --mailbox ~/code/todo/agent-coord.md \
  --coordination C007 \
  --sender "peer:/root" \
  --receiver "codex:/root" \
  --status ACK \
  --proof "proof-from-the-open" \
  --message "received"
```

`PING` uses the same command with `--status PING`. The watcher registers before
capturing its baseline, so all baseline content—including its local `OPEN`, a
wrong route or token, and a receipt that arrived before `ARMED`—is ignored. If
the fresh proof already has a matching baseline receipt, the helper emits
`PREARM-RETRY`, publishes a new `OPEN` with a new event and proof, and rearms
within the original deadline. A manually observed receipt never substitutes for
this event path.

The named monitor sends `ARMED` to its root using native collaboration. When
stdout yields a peer line, it sends that exact line to the root using the native
`send_message` operation, then starts another `open-watch` immediately with a
fresh generated request unless the shared concern is settled. Only after that
native delivery may the root report `synced`; it names the timestamp in the
first field and the peer event from `event=...`, plus the newly armed watcher.
This recurrence belongs to the monitor agent, not to a polling loop, shell
daemon, manual mailbox read, or user babysitting.
