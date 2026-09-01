# ~/code layout

- `~/code/<project>` — personally owned projects.
- `~/code/resources/` — read-only third-party context; check licenses before reuse.
- `~/code/clients/` — confidential client work; never expose it to other projects or services.
- Data directories such as `north-data` and `agent-data` are runtime state, not projects.

## Repository layout

`~/code/<project>` is a container, not a checkout:

```text
~/code/<project>/
~/code/<project>/main/
~/code/<project>/worktrees/<slug>/
~/code/<project>/pins/<full-object-id>/
~/code/<project>/pins/<full-object-id>.pin
```

`main/` is clean, read-only product. Work happens in a bare-named lane under
`worktrees/` and lands through a ref:

```text
git -C ~/code/<project>/main worktree add ~/code/<project>/worktrees/SLUG -b SLUG
safe-push --to main
git -C ~/code/<project>/main pull --ff-only
```

Pins are immutable detached checkouts consumed outside the repository. Never
repoint one. Advance a consumer to a new hash-named pin, then retire an orphan
only with `pin-retire` and an exact `consumer-main:` record for each consumer.

Client repositories retain their owner namespace and use the same container
shape. Resource repositories are read-only and get neither worktrees nor pins.

## Paths in documentation

Use `repo:path` for repository files, such as `north-v2:src/main.rs`. Use an
absolute path only for state that genuinely has a fixed location.

## Enforcement

The launch-critical worktree guard refuses writes to protected `main/`
checkouts and pins, including writes attempted through shell commands. A dirty
`main/` is human work-in-progress: never commit, stash, reset, or clean it.

`fram`, `north-v2`, and `beagle` are launch-critical. Their primary checkouts
are production inputs, so agents always edit them in a worktree lane.
Uncommitted North-v2, Beagle, or NixOS changes are absent from promoted runtime
or commit-snapshot rebuilds.
