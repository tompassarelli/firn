---
name: repo-safety-reference
description: >-
  Full repository notes for lane/pin lifecycle, destructive targets, process ownership, and guard recovery.
---

# Repository safety: full notes

## Topology and rationale

The repository container separates clean human/launch state at `main/`,
writable owned lanes at `worktrees/<slug>/`, and immutable consumer pins at
`pins/<full-object-id>/`. Those roles prevent an unrelated edit from entering
a build or changing another consumer's runtime.

Cleanliness and merged ancestry do not prove a lane is abandoned. An actor may
own a clean lane before its first write. Only its owner or accountable parent
may retire it after settlement; unknown ownership preserves it.

## Create and land an owned lane

Commands below use placeholders; resolve the exact project and slug first.

```bash
git -C ~/code/<project>/main worktree add \
  ~/code/<project>/worktrees/SLUG -b SLUG
```

Edit, check, and explicitly stage each intended path in the lane, then commit.
Let pre-commit finish before running `safe-push --to main` separately.
Fast-forward a clean main with `git -C ~/code/<project>/main pull --ff-only`.
Never stash/reset/clean/commit a dirty main or rewrite published history.

For a blocked cross-turn landing, keep the commit, remaining check, resume
trigger, and successor in the required continuity record. Lane-local build
outputs stay in the lane (or a deliberate temporary target), not the container.

## Immutable pins

A same-name `.pin` sidecar is mutable metadata recording every real consumer.
Create a new detached pin to move a consumer; never mutate or repoint the old
checkout.

```bash
PIN_OBJECT_ID=FULL_GIT_OBJECT_ID
git -C ~/code/<project>/main worktree add --detach \
  ~/code/<project>/pins/$PIN_OBJECT_ID $PIN_OBJECT_ID
```

The sidecar records one exact `consumer-main: ~/code/CONSUMER/main` per
repository consumer. After all consumer moves land, use:

```bash
pin-retire --consumer-main ~/code/CONSUMER/main -- \
  ~/code/<project>/pins/OLD_FULL_GIT_OBJECT_ID
```

Repeat the consumer argument for every recorded consumer. The helper checks
cleanliness, detachment, naming, publication, registration, agreement, and
remaining references before removal. Git history recovers committed content;
it does not recover untracked work or prove live consumers are finished.

## Destructive operations and denials

Resolve literal targets and recovery before deletion. A cache, dependency
directory, ignored file, or tracked-clean file is only a candidate: its name or
Git status is not permission to remove it. Personal/untracked work, broad roots,
checkout roots, live pins, state stores, and peer lanes remain protected.

Never derive a target from unresolved variables or globs. A guard denial is
evidence to select the sanctioned route, not a reason to disable the guard.
Stop for unresolved ownership, destructive scope, secret findings, or exposure.

## Processes and credentials

Signal only a process/tree you own, by exact PID or genuinely unique scoped
pattern. A shared session or matching executable name does not establish
ownership. Use the sanctioned capacity wrapper for contained heavy work.

Purpose-built authentication may consume an existing key, such as through
`ssh-add` or an SSH identity option. Naming/using a credential is distinct from
printing its value. Keep secrets out of source, logs, chat, and arguments.
