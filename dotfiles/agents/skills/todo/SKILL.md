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
id = "fram-proposition-boundary"
title = "Separate proposition identity from assertion identity"
shape = "project"
life = "active"
updated_at = "2026-08-14T11:36:50+08:00"
owners = ["codex:/root"]
depends_on = []
blocks = ["fram-structural-declarations"]
conversation_ids = ["codex:019ffd07-c27b-7943-8a66-553dff2ae98b"]
coordination = ["agent-coord.md#C007"]

[[lane]]
repo = "fram"
worktree = "~/code/fram/worktrees/proposition-boundary"
branch = "proposition-boundary"
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

For a task, add root fields `realizes`, `assigned_to`, and `delegated_by`. For a
project, add `plan`. Shape changes are recorded by updating `shape`, `life`, and
the Current state/Decisions sections; history remains in its conversation and
repository checkpoints.

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
dedicated monitor agent; a named hash/mtime watcher with bounded polls is an
acceptable fallback. The owner must be able to state and reap every watcher.

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
