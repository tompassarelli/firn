# Clause modules

These compiler-to-Nix integration checks follow
`north:socrates/skills/testing/SKILL.md`. CI regenerates the committed Nix
outputs with `firn repo build` and rejects drift with `git diff --exit-code`.
The full whiterabbit build checks their Nix evaluation.

`nixos-config:native/nix/btop.clause` and `nixos-config:native/nix/jq.clause`
use the shared declaration source `nixos-config:native/nix/nixpkgs.clause`.
The same checked module form supplies fifteen package modules, including
ripgrep, fd, tree, wget, unzip, and curl.

Build `clause-workbench` from the exact revision in
`nixos-config:config/clause-revision`, read its `authoring-card`, and pass that
executable to `nixos-config:native/nix/resolver.test.sh`. The resolver discovers
and compiles the selected sources and checks tag selection and source ownership.
Generated fixtures remain under `nixos-config:.firn-build/nix-resolver/`.

`nixos-config:modules/<name>/tags.clause` explicitly selects
`nixos-config:native/nix/<name>.clause`, exporting `<name>-module`, as the
module source. The metadata file owns automatic and opt-in tag membership, for example:

```clause
import "../../native/module_metadata.clause"

export metadata(): ModuleMetadata
  module-metadata(["cli-tools"], [])
```

The resolver compiles each source once and calls its checked metadata export.
The shared record requires `tags` and `optIn`, both `Sequence<Text>`; malformed
foreign results reject. btop and jq retain automatic `cli-tools` membership.
Kitty uses `module-metadata([], ["terminal"])`; Ladybird opts into `browsers`.
Enabling either tag alone excludes its opt-in module. A competing
`nixos-config:modules/<name>/default.bnix` or a missing Clause source is an error. Modules without this metadata file continue to use
their existing Beagle source. Shared declaration files are not module entries.

Run `firn-runtime-update` after changing `nixos-config:config/clause-revision`.
It builds that exact revision from `~/code/clause/main` (or the explicitly
selected `FIRN_CLAUSE_REPO`) into the out-of-store user runtime and binds it
automatically for tag, inventory, and build commands. The launchers reject
a checkout whose declared revision differs from the installed runtime.
No `FIRN_CLAUSE_WORKBENCH` setting is needed; an explicit setting must identify
the same produced executable. The compiler's shared libraries are retained
by user runtime GC roots without adding the compiler to the system closure.
The build driver
discovers the selected source, compiles it to the existing
`nixos-config:modules/<name>/default.nix`, and retains the flake's ordinary
directory discovery. `firn repo diff native/nix` checks the generated outputs.
Both source forms use the same tag resolver. These commands do not activate a
system configuration.

With `BEAGLE_PATH` set to the repository's Beagle compiler, run
`nixos-config:native/nix/resolver.test.sh` with the pinned workbench executable
as its argument. It builds the resolver/build graph, discovers and compiles the
five actual sources in a fixture, checks automatic and opt-in selection and
generated outputs, and rejects conflicting or missing
source ownership and wrongly typed metadata exports.

The three Clause sources follow
`clause:test-vectors/authoring/static-modules/` at revision
`51e9e126af7029945b1e08bdb4763e6a058061e9`, under MIT, copyright 2026 Tom
Passarelli. The matching notice and license are retained in
`nixos-config:LICENSE-MIT`.
