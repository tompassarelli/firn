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

**Don't** run `firn host rebuild` to verify — that activates the system (sudo, generation switch, reboot-relevant). Leave that to the user. Use `nix build --no-link` for build-only verification.

**Don't** run `nh` directly either; same reason — it switches the system. `firn host rebuild` wraps `nh` already; it's the user's command.

Only verify whiterabbit. Skip thinkpad-x1e.
