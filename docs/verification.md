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

`firn rebuild` (the sanctioned wrapper) IS agent-runnable — policy change 2026-07-08 — once `firn build` + `firn validate` are green, your own changes are committed, and no build input is dirty: zero uncommitted `*.bnix`/`*.nix`/`flake.lock` anywhere in the tree (flakes build the working tree; a dirty build input bakes another session's WIP into a generation no commit maps to). Other sessions' dirty non-build files don't block. `firn rollback` / the boot menu undo a switch.

Before those gates, rebuild refreshes the committed `main` revisions of the local
`~/code/beagle`, `~/code/fram`, and `~/code/north` inputs. It updates no remote
inputs and automatically commits only the derived `flake.lock` change. A dirty
local checkout, non-`main` branch, or pre-existing lockfile edit aborts before
the build, so local development stays one-command without consuming uncommitted
tracked source. Untracked editor and daemon state does not block the refresh.

**Don't** run `nh` or `nixos-rebuild` directly — only the wrapper; the firn-guard hook denies the bypasses. `firn update` (wholesale input bumps) stays the user's.

Only verify whiterabbit. Skip thinkpad-x1e.
