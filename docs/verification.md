# Verification

There's a tiered loop — pick the right rung for the change.

**Rung 1 — fast (~5s, default for most edits):**

```bash
./scripts/firn-build       # regenerate any .nix whose .bnix changed
./scripts/firn-validate    # schema-driven path + type check
```

`firn-validate` catches unknown option paths, type mismatches (bool/str/int/listOf/nullOr/enum/attrsOf-leaf), enum violations with did-you-mean — at file:line:col precision on the value. Almost every typo/wrong-type bug surfaces here in seconds. This is the right verification for module/tag/host edits where the change is "set X to Y" or "enable Z".

**Rung 2 — drift check (when refactoring beagle/nix itself, or sanity-checking that hand-edited `.nix` matches what beagle would emit):**

```bash
firn repo diff             # re-emit every .bnix and unified-diff vs committed .nix
```

**Rung 3 — full evaluation (only when Rung 1 isn't sufficient — e.g. you touched flake inputs, complex module logic, evaluation-time conditionals, or anything the static checker can't see):**

```bash
nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link
```

This catches things the validator can't: input mismatches, evaluation errors in submodule freeformType paths, build-time failures.

`firn rebuild` is the sanctioned agent-runnable wrapper. Run the relevant checks
and commit your own changes first.

A rebuild builds a **commit snapshot** (`git+file://<repo>?rev=HEAD`), never the working tree: uncommitted state — yours or any concurrent session's — can neither block it nor leak into a generation. The one gate that remains YOURS: **commit your own changes first**, or they simply won't be in the build (the pipeline prints exactly which in-flight files it excluded). Every generation maps to a commit by construction. `firn rollback` / the boot menu undo a switch.

Firn regenerates `.nix` (stale committed outputs are self-healed with a
mechanical commit; outputs downstream of in-flight WIP keep their committed
versions), validates the snapshot in a detached temp worktree, builds the host
closure with the committed lock, and switches that **exact store path** without
a second evaluation. `--skip-checks` still builds and switches the HEAD snapshot
with the committed lock; it skips validation.
Untracked files are a printed warning ("not in this build"), no longer a hard
stop.

**Don't** run `nh` or `nixos-rebuild` directly — only the wrapper; the firn-guard hook denies the bypasses. `firn update` (wholesale input bumps) stays the user's.

Only verify whiterabbit. Skip thinkpad-x1e.
