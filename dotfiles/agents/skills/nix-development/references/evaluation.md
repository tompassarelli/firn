# Evaluation and completion

## Git-backed inputs

For a new flake, evaluate untracked work with an explicit `path:` flake URL, or
stage only the enumerated new files before using Git-backed `.`; Git flakes do
not see untracked files. Never use blind staging.

## Check the output actually requested

Use the narrowest decision-changing sequence:

1. Validate and regenerate the authoritative source format when applicable.
2. Evaluate the exact output being added with `nix eval`, `nix flake show`, or
   `nix develop` rather than assuming syntax success proves evaluation.
3. Enter the declared environment and print the load-bearing tool versions.
4. Run the project's nearest build or test through `nix develop --command`.
5. Run `nix build` for a package output, `nix run` for an app interface, or
   `nix flake check` for declared checks only when that output is part of the
   requested artifact.

Fix the flake when the declared workflow fails; do not fall back to assembling
PATH entries, invoking store binaries directly, installing a system toolchain,
or documenting an ad-hoc command as the normal route. Distinguish evaluation
failures, missing build inputs, source filtering, lock drift, and the project's
own compile/test failures before naming a cause.

Complete when a fresh `nix develop` or the requested flake output supplies the
declared environment and the nearest real project command succeeds. Report the
output added, pinned inputs or toolchain, observed command, and any platform or
packaging boundary not exercised.

## Interpreting failures

Parsing proves source shape; evaluation proves an output can be selected; a
real command proves the declared environment supplies its needs. Choose the
nearest missing boundary rather than rerunning every stage. A source-filtering
failure can come from an untracked file, while a compiler error inside the
shell is a product failure—those require different repairs.
