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
within a bound, and be reaped with its supervisor. The helper derives
`PAIR-CHANNEL` as the full SHA-256 digest of the JSON-encoded, lexicographically
ordered exact root identities, prefixed with `pair-`. Prove the route with one
addressed transport round trip:

```text
- [timestamp][PAIR-CHANNEL][sender -> receiver][OPEN] event=EVENT session=SESSION round=N proof=TOKEN expires=MILLISECONDS message=EXACT-CONCERN
- [timestamp][PAIR-CHANNEL][receiver -> sender][RECEIVED] event=EVENT reply-to=OPEN-EVENT session=SESSION round=N proof=TOKEN received-session=OPEN-SESSION
```

Messages remain append-only while a concern is live. `RECEIVED` is a neutral
transport fact, never semantic acceptance or work acknowledgement. Use the
separate `work-ownership-v1` contract for ownership. On delivery timeout,
retain ownership and report the exact failure; the next bounded helper
invocation creates fresh events. Before stopping the monitor, settle every peer
payload already delivered to the root.

### Executable duplex bootstrap

Resolve the helper relative to the authoritative `SKILL.md` already read for
this invocation, never from a projection, remembered path, or a second
`agents path` lookup:

```bash
# todo_skill_dir is the directory containing that authoritative SKILL.md.
mailbox_helper="$todo_skill_dir/scripts/cross-supervisor-mailbox.mjs"
```

Each supervisor's named monitor starts one copy of the same command. `--local`
is that monitor's root and `--peer` is the other root; the peer runs the command
independently with those two values reversed:

```bash
bun "$mailbox_helper" duplex \
  --mailbox ~/code/todo/agent-coord.md \
  --local "codex:/root" \
  --peer "peer:/root" \
  --message "synchronize the shared concern"
```

The normal invocation has no operator-chosen coordination ID or status. The
helper derives one stable order-independent channel from the exact local/peer
pair. The shared concern remains `message=` payload. The helper generates its
local session, events, timestamps, proofs, and expiry, appends its `OPEN`,
discovers the peer's exact unexpired `OPEN`, and appends `RECEIVED` using that
peer event, proof, and session. It also watches for the exact `reply-to`, round,
proof, and receiving session matching its own `OPEN`. The operator must never
be asked to copy a channel, line, event, or token between roots.

The subscription is installed before the baseline is captured. Baseline
discovery accepts only an exact, unexpired peer `OPEN` that this local root has
not previously answered. This makes either startup order safe while rejecting
expired or already-replied stale events. Current and future processing also
rejects a local route, another sender or receiver, another pair channel, a
receipt with the wrong `reply-to` or proof, malformed ordered fields, and
duplicate event IDs. Each peer `OPEN` receives at most one helper-owned receipt,
and each round delivers at most one peer `OPEN`.

`OPENED`, `ARMED`, `ROUND-COMPLETE`, and `REARMED` are diagnostics on stderr.
Each stdout line is one JSON object containing `channel`, `round`, the unchanged
`peerOpen`, parsed `peerMessage`, and unchanged correlated `receipt`. It appears
only after the helper has both answered that peer `OPEN` and matched the peer's
`RECEIVED` to its own `OPEN`. The named monitor sends `ARMED` and every stdout
delivery to its root with the provider's native `send_message` operation. Only
then may the root report transport `synced`, naming the peer event and receipt
and confirming the next round is armed. That claim never means the peer accepted
the message's semantics.

The defaults are two rounds and 300000 milliseconds. Explicit `--rounds` is
bounded from 1 through 32 and `--timeout-ms` from 1 through 300000. Completing
all rounds exits zero; timeout exits 124; argument, watch, or read failure exits
2. While the concern remains live, the named monitor immediately re-invokes the
same command after zero exit, so the protocol stays armed without operator
involvement. The helper itself remains a bounded file-event process with no
polling, daemon, provider credential, manual mailbox read, compatibility path,
or transcript dependency.
