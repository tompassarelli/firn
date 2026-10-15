# Verification

Run `firn check` before building. Pre-push and CI run the same command:

```bash
firn check
```

It runs `nix flake check --no-build`, then evaluates every entry in the
flake's `nixosConfigurations` to its `system.build.toplevel.drvPath`.
NixOS checks option types, rejects unknown options and enforces module
`assertions`. No system derivation is built. The command then runs
`statix check`, `deadnix --fail` and `nixfmt --check` over the Nix sources.
The tools come from the checkout's locked nixpkgs when absent from PATH.

For editor diagnostics, configure `nixd` or `nil` as your Nix language server.
With nixd, point its NixOS option expression at the selected host's `options`,
for example `(builtins.getFlake "/absolute/checkout").nixosConfigurations.whiterabbit.options`.
Editor setup is optional and is separate from the command gate.

If changing tags or module metadata, run `firn repo build` before the check
so the resolved host composition is current. Check private overlay flakes
from their checkout too; their hosts and secrets are evaluated there.

The existing `.github/scripts/host-diff.sh select` compares base and head
host derivations without building. `build` reuses unchanged derivations and
builds only changed ones. Snapshots use path flakes to exclude Git revision
metadata from the comparison; the base is cached by Git tree and Nix version.
For a source-only rewrite, every host must be reported unchanged.

After checks and committing, use `firn rebuild` for the laptop and
`firn host deploy nexus` from the published checkout for Nexus. Rebuilds use
an exact committed snapshot, build the host closure and activate that exact
store path. Uncommitted work cannot enter a generation. Verify the printed
snapshot and the requested installed result. Do not invoke `nixos-rebuild`
or `nh` directly.

Automated tests follow the testing skill: reuse results whose inputs have not
changed, retain meaningful properties and recorded scenarios, and never
weaken an expectation or retry a flake to green.

`FIRN_REPO="$PWD" dotfiles/bin/firn-runtime-update` builds the locked
`tools/firn` Rust crate through machine-capacity and installs `firn-tools` in
the atomic CLI runtime. Agent registrations retain `firn-system-policy`, whose
one-line adapter execs `firn-tools system-policy`. Runtime promotion and
`agents sync` activate this change without a system rebuild.
