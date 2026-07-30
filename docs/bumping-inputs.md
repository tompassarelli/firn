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

**`firn update` moves every input forward; an ordinary `firn rebuild` no longer
auto-plans any local input.** Fram adopts a reviewed revision through
`north-coord-runtime promote`, which is an attested runtime transaction and does
not spend a rebuild; North and Beagle enforcement adopts through
`north-enforcement-promote`. The flake pin still records what a generation was
built from, but it is no longer the way a verified local revision reaches the
running system.

North and Beagle are deliberate dev-channel inputs. Ordinary rebuild planning
never advances them. A release operator must first build and verify the intended
40-character revision through an explicit exact-revision input override, then
settle only that verified pointer:

```bash
~/code/nixos-config/main/scripts/firn-sync-local-inputs --commit north=<verified-rev>
~/code/nixos-config/main/scripts/firn-sync-local-inputs --commit beagle=<verified-rev>
```

`--commit` is settlement, not verification. It confirms that the requested
revision is still the input's committed local `main`, remains a fast-forward
from the locked revision, resolves exactly through the targeted lock update,
and does not rewrite an unrequested pin. A moved input,
foreign lock or flake-source edit, resolution race, or failed mechanical commit
defers with a notice and exit 0; it never substitutes an unverified revision.
Do not use `firn update` for a North or Beagle development release — that is the
wholesale remote-input bump path.

All exact-revision builds evaluate `git+file://<repo>?rev=<commit>` URLs, so no
working tree can leak into or block the closure. `--skip-checks` builds the HEAD
snapshot with the committed lock and never plans the Fram pin. Untracked
editor/daemon state is ignored, and remote inputs such as nixpkgs remain pinned.

After a local config edit (enabled a module, flipped a tag) you still want `firn rebuild`; when the local input revisions are already current, the refresh is a no-op. Reach for `firn update` only when you deliberately want newer remote package inputs; `--no-rebuild` is the middle ground (advance them now, defer installation). Either path remains a gate: a failed refresh, fetch, schema extraction, or validation exits before switching.
