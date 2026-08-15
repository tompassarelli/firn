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

**`firn update` moves every input forward; `firn rebuild` uses the committed
`flake.lock` unchanged.** Use `firn update` only when deliberately advancing
remote package inputs.

Rebuilds evaluate the committed repository snapshot, so working-tree state
cannot enter the closure. `--skip-checks` still uses the committed lock.

After a local config edit (enabled a module, flipped a tag), use `firn rebuild`. Reach for `firn update` only when you deliberately want newer remote package inputs; `--no-rebuild` is the middle ground (advance them now, defer installation). Either path remains a gate: a failed fetch, schema extraction, or validation exits before switching.
