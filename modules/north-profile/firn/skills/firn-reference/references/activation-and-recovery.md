# Committed activation and recovery

## Snapshot semantics

`firn repo build` plus `firn repo validate` is the default loop.
`firn repo diff` re-emits targets and compares them with committed `.nix`.
When static validation cannot see a build-time issue, use:

```text
nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link
```

`firn rebuild` snapshots committed `HEAD`, validates that snapshot, builds it,
and switches the system. Its output names in-flight working-tree files excluded
from the snapshot and the exact revision being activated.

Commit only your owned paths. The build snapshot intentionally excludes
uncommitted changes, including other actors' work. A dirty unrelated checkout
does not need to be stashed or repaired for your snapshot.

System switching is required for an install request; policy-only out-of-store
edits instead use agent sync. A successful source check proves configuration
shape, not installed availability. Verify the requested program after switching.

## Progress and delay

A system build may spend most of its time downloading cached closures. Inspect
existing progress and measured throughput before diagnosing a stall. Preserve
in-flight work; a forecast miss alone is not a reason to restart.
Use only the sanctioned Firn entrypoints and the named host.

## Exact recovery

Select an exact positive decimal generation already present and older than the
active one:

```text
firn rollback <generation>
```

Firn resolves the generation to one Nix store path containing an executable
`switch-to-configuration` and refuses before mutation if it cannot. On success,
run `firn host gen` and require `current:` to equal the requested generation.
After a failed activation, inspect the same state before retrying because the
profile may already have changed.

Rollback is a live-state operation, not an automatic response to a slow build.
Resolve the actual failure and current generation first. The command targets
one validated generation; do not replace it with broad profile deletion.
