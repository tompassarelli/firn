---
name: repo-safety-reference
description: >-
  Detailed repository-safety reference for worktree creation and landing, pin
  manifests and retirement, destructive-target classification, scoped process
  control, credentials, and guard-denial recovery. Use after
  repo-safety-distilled routes here.
---

# Repository safety reference

`repo-safety-distilled` owns the boundaries and stop rules. This unit provides
the exact lifecycle procedures and classification examples.

## Repository topology and lane lifecycle

The repository container has three slots: clean `main/`, writable ephemeral
`worktrees/<slug>/`, and immutable `pins/<full-object-id>/` checkouts.

```bash
git -C ~/code/<project>/main worktree add \
  ~/code/<project>/worktrees/SLUG -b SLUG
# edit, check, explicitly stage, and commit in the lane
safe-push --to main
git -C ~/code/<project>/main pull --ff-only
```

Commit coherent checkpoints and land each after its relevant check passes. If
an environmental failure or moving dependency prevents landing, preserve a
restart-grade record with the commit, remaining check, resume trigger, and
successor. Prove a lane is superseded by content before reaping it.

## Pin lifecycle

A pin's same-name `.pin` sidecar is mutable metadata and names every real
consumer. To advance a consumer, create a new detached pin from the clean
checkout and update the consumer:

```bash
PIN_OBJECT_ID=FULL_GIT_OBJECT_ID
git -C ~/code/<project>/main worktree add --detach \
  ~/code/<project>/pins/$PIN_OBJECT_ID $PIN_OBJECT_ID
```

The sidecar keeps one exact
`consumer-main: ~/code/CONSUMER/main` record per repository consumer. After all
consumer moves land, retire the old detached pin with the exact recorded set:

```bash
pin-retire --consumer-main ~/code/CONSUMER/main -- \
  ~/code/<project>/pins/OLD_FULL_GIT_OBJECT_ID
```

Pass an additional `--consumer-main` for every recorded consumer. The helper
checks cleanliness, detachment, naming, publication, registration, consumer
agreement, and remaining references before removing the checkout and sidecar.

## Destructive-target classification

Known disposable targets include absent paths, caches and temp hierarchies,
dependency directories such as `node_modules`, ignored files, and tracked clean
files. Untracked work and personal data require an interactive reviewed
decision. Broad roots, checkout roots, live pins, state stores, and peer lanes
are outside the destructive target set.

Use literal validated paths. If a variable is unavoidable, require it with
`${TASK_SPECIFIC_VAR:?}` before expansion; never combine an unresolved variable
with a destructive glob. A reviewed tripwire exception is bracketed by
`agents off tripwire-guard` and `agents on tripwire-guard`.

## Process and credential examples

Use `kill <pid>` or `pkill -f '<unique-pattern>'` for a process you own. Code
that must reap a process subtree runs as PID 1 in its own namespace, for
example with `unshare --user --map-current-user --pid --fork --kill-child`.

Purpose-built commands such as `ssh-add <key>` may load an identity, and SSH
identity options may name it. Authentication is distinct from exposing its
contents.
