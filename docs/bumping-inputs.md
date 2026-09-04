# Bumping inputs

To bump nixpkgs and surface deprecations the schema-driven way:

```bash
firn repo upgrade dry-run  # preview the bump; mutate nothing
firn repo upgrade now      # advance flake.lock, refresh schema, diff, validate
firn rebuild               # build and switch the committed lock
```

The diff phase highlights any **removed** or **type-changed** option paths that this repo references — those are the actual breakage candidates, not the thousands of unrelated changes you'd see in a raw `nix flake update` log.

**`firn repo upgrade now` moves every input forward; `firn rebuild` uses the
committed `flake.lock` unchanged.** Upgrade only when deliberately advancing
remote package inputs.

Rebuilds evaluate the committed repository snapshot, so working-tree state
cannot enter the closure.

After a local config edit, use `firn rebuild`. Run `firn repo upgrade now` only
when you deliberately want newer remote package inputs. Agents may run it in
their owned worktree when advancing inputs is part of the requested outcome,
then must inspect and commit the exact result before rebuilding. A failed fetch,
schema extraction, or validation exits before the lock is ready to apply.
