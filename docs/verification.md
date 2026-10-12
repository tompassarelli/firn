# Verification

Automated tests follow `north:harness/skills/testing/SKILL.md`: keep only its
five kinds with a unique mutant kill; delete scaffolding. Run affected tests
once locally and suites, sweeps and properties on CI or the farm on every push.
Never retry flakes to green, weaken expectations or use wall time as a budget.

There's a tiered loop — pick the right rung for the change.

**Rung 1 — fast (~5s, default for most edits):**

```bash
firn repo build       # regenerate any .nix whose .bnix changed
firn repo validate    # schema-driven path + type check
```

`firn repo validate` catches unknown option paths, type mismatches (bool/str/int/listOf/nullOr/enum/attrsOf-leaf), enum violations with did-you-mean — at file:line:col precision on the value. Almost every typo/wrong-type bug surfaces here in seconds. This is the right verification for module/tag/host edits where the change is "set X to Y" or "enable Z".

**Rung 2 — drift check (when refactoring source or checking generated output):**

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

A rebuild builds a **commit snapshot** (`git+file://<repo>?rev=HEAD`), never the working tree: uncommitted state — yours or any concurrent session's — can neither block it nor leak into a generation. The one gate that remains YOURS: **commit your own changes first**, or they simply won't be in the build (the pipeline prints exactly which in-flight files it excluded). Every generation maps to a commit by construction. `firn rollback <generation>` / the boot menu undo a switch. Rollback requires an exact positive generation number, verifies that it exists and is older than the active NixOS generation, resolves its immutable store path, then activates it through the same effect boundary as rebuild. It never guesses “previous” or “latest.”

Firn regenerates `.nix`, validates the snapshot in a detached temp worktree, builds the host
closure with the committed lock, and switches that **exact store path** without
a second evaluation. Untracked files are reported and do not enter the committed
build snapshot.

**Don't** run `nh` or `nixos-rebuild` directly — only the wrapper. An agent may
run `firn repo upgrade now` in its owned worktree when the requested outcome
includes advancing inputs, then must inspect and commit the exact result before
rebuilding.

Verify whiterabbit and nexus.

The drift landing check regenerates sources, builds
`checks.x86_64-linux.nix-syntax`, and runs `.github/scripts/host-diff.sh build`
with `SAFE_PUSH_LAND_BASE` and `SAFE_PUSH_LAND_HEAD`. The selector evaluates all
NixOS and Darwin hosts in both Git snapshots, reports unchanged derivations as
reused, and builds only changed derivations. `select` reports the same comparison
without building. Removed hosts are reported; added hosts are built. A change
touching only `docs/` or `*.test.sh`/`*.test.py` skips host evaluation. Both
snapshots evaluate in parallel, and the base result is reused from
`~/.cache/firn/host-drvs` by Git tree hash and Nix version. Compiler drift is
skipped when a committed clean tree's compiler input hash (every `.bnix`,
`.clause`, `.nix` and `native/` blob, the installed runtime version and the
Beagle revision) already passed, recorded in `~/.cache/firn/compiler-drift`.

Snapshots use path flakes to exclude Git revision metadata from the comparison;
deployment still uses committed snapshots through `firn rebuild`. File references
must use individual paths rather than strings carrying the entire flake root.
`checks.x86_64-linux.host-whiterabbit` also exposes the system build as a reusable
check. The syntax check hashes only Nix files, so docs edits reuse it. Compiler
drift remains outside the pure checks because its Beagle and Clause runtimes are
installed out of store.

The schema transaction suite keeps the SHA-256 `abc` vector from
[RFC 6234, section 8.5](https://www.rfc-editor.org/rfc/rfc6234.html#section-8.5)
as its external reference, separately from generated schema properties.

Generated pure-core properties use fixed seeds: 128 inputs locally and 512
in CI (rebuild uses 16 and 64). Fixed scenario tables run once; changing only
an identifier is not a generated property. Views checks child-result
conservation with generated statuses and streams. Decoder references use
recorded Beagle schemas and NixOS generation output in `native/fixtures/`.
Authoring checks real Git staging and compiled Galileo/Nix behavior.

`modules/nexus-checks/default.test.sh` checks recorded OpenSSH/loginctl output
once, then generates numeric health inputs, warning sets and alert decisions.
The boot-coupling measurement compiles the real module metadata bodies in one
Clause bundle so the local check covers the whole catalog without starting a
compiler for each module.
