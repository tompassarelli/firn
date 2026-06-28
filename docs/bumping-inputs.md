# Bumping inputs

To bump nixpkgs and surface deprecations the schema-driven way:

```bash
firn update                # headline verb: bump every input THEN rebuild (chains `repo upgrade now` + `host rebuild`)
firn update --no-rebuild   # fetch only: advance flake.lock + schema, install nothing
firn update --dry-run      # preview the bump; mutate nothing
firn repo upgrade now      # underlying-graph form of `firn update --no-rebuild`: snapshot, nix flake update, re-extract, diff, validate
firn repo upgrade dry-run  # underlying-graph form of `firn update --dry-run`
```

The diff phase highlights any **removed** or **type-changed** option paths that this repo references — those are the actual breakage candidates, not the thousands of unrelated changes you'd see in a raw `nix flake update` log.

**`firn update` moves the lock forward then applies it; `firn rebuild` applies the lock you already have.** That's the whole distinction — `update` mutates flake.lock (new nixpkgs/inputs) then switches; `rebuild` builds + switches against flake.lock unchanged. After a local-only edit (enabled a module, flipped a tag) you want `firn rebuild` — `firn update` would drag in surprise upstream drift. Reach for `firn update` only when you deliberately want newer package versions; `--no-rebuild` is the middle ground (advance the lock now, defer the install). The bump is a **gate, not a prelude**: a failed fetch / schema-extract / validate `exit 1`s before the rebuild is reached, so a known-broken config is never switched. (`firn` for exact flags.)
