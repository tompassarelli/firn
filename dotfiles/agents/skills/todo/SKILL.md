---
name: todo
description: >-
  Use whenever work could remain in flight: before creating a worktree,
  delegating a lane, waiting on another actor, writing a handoff, or parking a
  thread, plan, task, project, or resource. Maintains restart-grade Markdown +
  TOML records in the flat ~/code/todo/ directory and the acknowledged
  agent-coord.md mailbox protocol.
---

# todo — restart-grade continuity

`~/code/todo/` is the inventory of work whose continuity matters. A machine
restart must not require transcript archaeology or worktree archaeology to
discover what was active, who owned it, or how to resume it.

Create or update a record **before** the first mutation whenever work can
outlive the current response, creates a worktree, is delegated, waits on an
external event, or has more than one independently useful phase. A small
same-response action may use a short-lived record and delete it when the work
is genuinely complete. All live work must be enumerable from this directory.

## Storage contract

The folder stays flat. Use one Markdown file per independently resumable unit;
never create nesting or a `main/` directory. Use `<topic>-handoff-NN.md` for a
continuation of a specific execution lane and a stable descriptive name for a
long-lived thread. `agent-coord.md` and `AGENTS.md` are reserved singleton
files.

Each work record starts with TOML front matter and continues with Markdown:

```markdown
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

## Outcome

What must be true when this record can disappear.

## Current state

The last durable checkpoint, including exact revisions and what is dirty.

## Decisions

Only load-bearing rulings a replacement agent must preserve.

## Next actions

Ordered, executable steps from the current checkpoint.

## Verification

Checks already run and their observed results; name remaining release gates.

## Recovery and cleanup

How to resume safely, plus the exact conditions for landing, reaping lanes,
releasing coordination claims, and deleting this file.
```

Required root fields are `id`, `title`, `shape`, `life`, `updated_at`, and
`owners`. Include dependency, conversation, coordination, and lane fields when
they exist; use empty arrays only when their absence is meaningful. A lane is
one atomic mapping from repository to worktree, branch, owner, and state. Never
list a repository without the exact live worktree when a worktree exists.

Conversation IDs are stable provider/session identifiers, not copied transcript
paths. Recover one with `convo session <uuid>`. Paths use `repo:path` for files
inside a repository and `~`-anchored paths for fixed runtime locations and live
worktrees.

## Attempt, review, and debt receipt

An active execution record (a task or project that starts work, owns a lane, or
delegates) has one `[[attempt]]` before the work starts. This is the forecast
and staffing join point; proposals, inactive threads, and resources do not
invent estimates before they become execution. A non-delegated attempt still
records `model = "self"` and `role = "owner"`.
An `attempt` belongs only to a task or project, and a live lane makes that
record active execution even if its `life` field has not yet caught up.

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

`wall_time_estimate` is elapsed critical-path time; `agent_time_estimate` is
the summed agent execution time expected to be consumed. They coincide for one
uninterrupted worker but deliberately differ for queues, waits, and races.
An estimate may use a leading `~` or `under ` qualifier. Actual durations are
unqualified compact numbers, and `ended_at` must not precede `started_at`, so
the wall-time actual-to-estimate ratio remains derivable.
`calibration_sample_count` is the count of completed observations supporting
the estimate. `review_budget` is `none`, `owner`, or
`independent`; it is a named spending and assurance choice, never an implied
numeric craftsmanship score. A race has one `race` identifier on each attempt,
and every candidate receives its own model, route, and outcome.

At settlement, update the same attempt with `ended_at`, `outcome`,
`wall_time_actual`, `agent_time_actual`, `queue_block_time_actual`,
`verification_time_actual`, and (for a race) `race_outcome`. These are
overlapping explanatory measurements, not numbers to add together: wall time
is the elapsed critical path, agent time is summed execution duration, and
queue/block and verification time explain portions of the path. If a duration
also records why the wait or verification occurred, split that text into
optional `queue_block_cause` or `verification_summary` instead
of storing prose in a time field. Add `reviewed_commit`, `review_outcome`
(`clean`, `findings`, or `not-run`), optional `review_summary` for one compact
result sentence,
`reviewer_model`/`reviewer_reasoning` for an independent review, and
`review_repair_time_actual` when review findings are repaired.
Then put one compact terminal receipt in `~/code/todo/estimate-calibration.md`.
That receipt carries the same estimate/actual fields plus model, reasoning,
route, role, assignment ID, outcome, and a concise overrun cause, so future
staffing can compare like attempts without copying live state into another
ledger. Derive the wall-time actual-to-estimate ratio from the two stored
values; do not duplicate that derivable value in the attempt. Record provider
cost or token actuals only when an authoritative source already supplies them.

Completion is not a vague quality certificate. An independent review consumes
one exact commit and records concrete findings and their disposition. If a
known quality gap is intentionally deferred, add a top-level `[[quality_debt]]`
entry with `attempt`, `path`, `invariant`, `severity`, `owner`, and
`exit_condition`. Remove it when the condition is proven. Do not use debt for
unbounded “polish later,” and do not review a clean area again without a new
change, finding, or named assurance reason.

## Shapes are semantic, not one universal state machine

Use the narrowest shape that is already true:

- `thread`: something whose continuity matters.
- `plan-draft`: an action/outcome/value story still being formed.
- `proposal`: a plan-draft offered for evaluation or adoption.
- `plan`: a solidified proposed journey from actions to desired outcomes whose
  value is asserted as worth pursuing.
- `project`: a plan whose execution has started; activity may be active or
  inactive without changing its shape.
- `task`: a delegated, assigned action from a plan. It realizes that plan; a
  possible or self-considered action is not automatically a task.
- `resource`: a person, book, article, SaaS service, AI agent, or other thing
  useful to the tracked work.

For a task, add root fields `realizes`, `assigned_to`, and `delegated_by`.
`realizes` is the exact `id` of a tracked plan or project: a project remains a
plan, now in execution. A project needs `plan` only when it starts a *distinct*
tracked plan record; then `plan` is that record's exact `id`. When one record
itself evolves from plan to project, preserve its identity and omit `plan`
instead of manufacturing a self-reference or symbolic pseudo-ID.

`requires` is the one stored direction of the work DAG: dependent to
prerequisite. Its internal values are exact record IDs; an external prerequisite
is explicitly prefixed `external:`. Derive reverse `blocks` topology and the
current unsatisfied `blocked_by` subset from `requires`; store neither. The same
exact-ID rule applies to `realizes`,
`plan`, `supports`, and `relates_to` whenever those fields name tracked records.

Shape changes are recorded by updating `shape`, `life`, and the Current
state/Decisions sections; history remains in its conversation and repository
checkpoints.

`life` is shape-specific. Do not force every record through `done`. Resources,
for example, can become `internalized`, `outdated`, `superseded`, or `archived`.
Delete a file when no continuity remains to be recovered; Git history is the
recovery mechanism for repository work, while completed non-git todo files may
only be recoverable from backups.

`reference` is not a resource subtype or a shape. It is a credibility relation:
one thing supports a claim. Record that as `supports = [...]` when needed.
`relates_to = [...]` records ordinary relation and must not imply evidentiary
support.

## Update discipline

Update the record at every externally visible phase boundary: ownership change,
new worktree, checkpoint commit, dependency change, block/unblock, verification
result, landing, or coordination message. Replace stale state; do not append a
chronological transcript. A replacement agent should be able to execute Next
actions without first opening the conversations.

Delete a work record only after every owned change is landed or deliberately
discarded, every worktree/branch disposition is explicit, every dependent item
has been updated, and no external actor is waiting for an acknowledgement.
Outdated or superseded notes with no remaining recovery value are deleted, not
kept as tombstones.

Runtime state, machine-managed data, end-user documentation, and ephemeral
scratch do not belong here.

## Coordination mailbox protocol

Editing `agent-coord.md` does not itself notify another agent. When two agents
coordinate through it, one named monitor must watch the file for the lifetime
of the coordination window and deliver changes to the owning agent. Prefer a
dedicated monitor agent or product monitoring primitive. A hash/mtime shell is
acceptable only when a live supervisor consumes its output on a bounded poll
and can re-invoke or message the owning agent. A background shell whose output
merely accumulates in an unread session is not delivery. The owner must be able
to name the watcher, the supervisor, the delivery bound, and how both are
reaped.

Prove the route with one addressed `OPEN` -> `ACK` round trip before relying on
it for work ownership. If the delivery bound elapses, the sender appends one
explicit delivery retry and treats the request as unacknowledged; silence never
transfers ownership or makes cleanup safe.

Messages are append-only while a claim is live:

```text
- [timestamp][C007][sender -> receiver][OPEN] request or claim
- [timestamp][C007][receiver -> sender][ACK] received and accepted/declined
- [timestamp][C007][sender -> receiver][UPDATE] changed checkpoint
- [timestamp][C007][sender -> receiver][DONE] terminal result and revision
```

`OPEN` is not delivery. The sender waits for `ACK`; the receiver writes it
promptly. A monitor reports every change, but only messages addressed to its
owner require action. Before yielding or stopping the monitor, reread the board
and settle every addressed `OPEN`/`UPDATE`, then terminate and reap the watcher.

When finishing a session with live work, refresh its record last. The next
session starts by reading the TOML headers, reconstructing the dependency graph,
then opening only the records and conversations on the ready path.
