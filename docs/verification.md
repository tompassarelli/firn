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
and commit your own changes first; `north rebuild request --why "<reason>"`
remains available when queued, coalesced execution is preferable.

A rebuild builds a **commit snapshot** (`git+file://<repo>?rev=HEAD`), never the working tree: uncommitted state — yours or any concurrent session's — can neither block it nor leak into a generation. The one gate that remains YOURS: **commit your own changes first**, or they simply won't be in the build (the pipeline prints exactly which in-flight files it excluded). Every generation maps to a commit by construction. `firn rollback` / the boot menu undo a switch.

Ordinary rebuild planning auto-plans no local input. Firn regenerates `.nix`
(stale committed outputs are self-healed with a mechanical commit; outputs
downstream of in-flight WIP keep their committed versions), validates the
snapshot in a detached temp worktree, builds the host closure with the committed
lock, and switches that **exact store path** without a second evaluation. It
does not rewrite or commit a local-input pin. Fram adopts a reviewed runtime
revision through `north-coord-runtime promote`; North and Beagle enforcement
adopt through `north-enforcement-promote`. Those attested runtime transactions
do not spend a rebuild.

Deliberately moving a North or Beagle flake pin is a separate two-step release:
first build and verify the host closure with an explicit exact-revision override
for the intended 40-character SHA; only after that build succeeds, settle the
same SHA with
`~/code/nixos-config/main/scripts/firn-sync-local-inputs --commit
north=<verified-rev>` or the corresponding `beagle=<verified-rev>` target. Do
not use `firn update`: it is the wholesale remote-input bump path, not local
dev-channel verification.

Targeted settlement rechecks the locked ancestry and current local `main`, then
requires the lock resolver to produce the exact built revision. A foreign lock
or flake-source edit, raced input, unexpected rewrite of any unrequested Beagle,
Fram, or North pin, or failed commit hook defers with a notice and exit 0.
Recovery is
commit-aware: if the mechanical commit lands immediately before an
exit/signal, the handler preserves that exact promoted lock and heals the
index/worktree to the new HEAD instead of restoring the obsolete pre-promotion
backup.
`--skip-checks` still builds and switches the HEAD snapshot with the committed
lock; it skips validation, while ordinary local-input planning remains empty.
Untracked files are a printed warning ("not in this build"), no longer a hard
stop.

**Don't** run `nh` or `nixos-rebuild` directly — only the wrapper; the firn-guard hook denies the bypasses. `firn update` (wholesale input bumps) stays the user's.

Only verify whiterabbit. Skip thinkpad-x1e.
