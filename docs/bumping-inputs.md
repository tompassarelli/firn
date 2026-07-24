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

**`firn update` moves every input forward; `firn rebuild` promotes only committed local development inputs.** On rebuild, Firn *plans* pin moves for `~/code/beagle`, `~/code/fram`, `~/code/orchestration`, and `~/code/north` (read-only — the lock is never provisionally mutated): committed `main` HEAD is eligible even when the checkout has tracked WIP, because the build pins the exact Git object and prints that the worktree changes are excluded. A feature branch still **holds its already-verified pin**. Planned moves ride the snapshot build as `--override-input` flags; the whole rebuild evaluates exact `git+file://<repo>?rev=<commit>` URLs, so no working tree (this repo's or any input's) can leak in or block. Only after the host closure builds is `flake.lock` re-pointed and mechanically committed ("refresh verified local inputs"); commit receives the exact revision the build verified and defers if HEAD moved meanwhile. Every other non-promotable state at that point — a foreign lock edit or hook failure — likewise defers with a notice and exit 0, because the switched generation already carries the verified revs. `--skip-checks` builds the HEAD snapshot with the committed lock and never promotes pins. Untracked editor/daemon state is ignored, and remote inputs such as nixpkgs remain pinned.

After a local config edit (enabled a module, flipped a tag) you still want `firn rebuild`; when the local input revisions are already current, the refresh is a no-op. Reach for `firn update` only when you deliberately want newer remote package inputs; `--no-rebuild` is the middle ground (advance them now, defer installation). Either path remains a gate: a failed refresh, fetch, schema extraction, or validation exits before switching.
