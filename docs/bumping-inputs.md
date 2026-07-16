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

**`firn update` moves every input forward; `firn rebuild` refreshes only committed local development inputs, then applies the lock.** On rebuild, Firn checks `~/code/beagle`, `~/code/fram`, and `~/code/north`: a checkout only *advances* its pin when its tracked source is committed and it sits on `main`. A checkout that isn't in that state — dirty tracked files (e.g. another session's WIP), or a feature branch — never blocks the rebuild: that input **holds its already-verified lock pin** for this run, with a printed old/HEAD notice, and promotes on a later rebuild once clean. The generation is always built from locked commits, so uncommitted work can never leak in either way. Advanced entries are refreshed provisionally, reported old→new, then run through generation, validation, and a host-closure source/package smoke build. Only a verified lock is mechanically committed; a failed gate restores the previous lock. `--skip-checks` uses the existing lock without refreshing it. No GitHub release or manual lock command is required. Untracked editor/daemon state is ignored, and remote inputs such as nixpkgs remain pinned.

After a local config edit (enabled a module, flipped a tag) you still want `firn rebuild`; when the local input revisions are already current, the refresh is a no-op. Reach for `firn update` only when you deliberately want newer remote package inputs; `--no-rebuild` is the middle ground (advance them now, defer installation). Either path remains a gate: a failed refresh, fetch, schema extraction, or validation exits before switching.
