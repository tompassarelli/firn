# Continuity records and dependencies

## A record is executable memory

Create one only when continuity is independently needed. Its value is that a
successor can take the next safe action without reconstructing a transcript.
Replace current state, preserve decisions that still constrain the work, and
remove completed trivia.

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

The values are an example, not facts to copy. Omit optional fields with no real
counterpart. Model/forecast metadata is not a prerequisite to a useful record.

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

Choose the narrowest true shape. A task record is not required merely because
an agent acts; a separate plan record is not required merely because work was
planned. Delete only after continuity, owned state, dependents, cleanup, and
awaited acknowledgements no longer need it.
