---
name: firn-reference
description: >-
  Detailed Firn reference for Beagle/Nix module authoring, host enablement,
  schema and compiler queries, focused project guides, verification rungs,
  committed rebuild snapshots, and exact generation rollback. Use after
  firn-distilled routes here.
---

# Firn reference

`firn-distilled` owns lifecycle decisions, boundaries, and stop rules. This
unit owns detailed authoring and recovery procedures.

## Source and build flow

```text
*.bnix --(firn repo build)--> *.nix --(firn rebuild)--> system
```

The flake reads the Git tree, so new source and generated targets must be
tracked. Beagle itself is documented by `beagle-authoring-distilled`.

## Add a module

Create `modules/<name>/default.bnix`, following an existing simple module:

```clojure
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [cli-tools]
   :options.myConfig.modules.<name>.enable (lib.mkEnableOption "...")
   :config (lib.mkIf config.myConfig.modules.<name>.enable
             {:environment.systemPackages (nix/with pkgs [<name>])})})
```

Then run:

```text
firn repo build
firn repo validate
git add modules/<name>/default.bnix modules/<name>/default.nix
```

Confirm a package first with `nix eval nixpkgs#<name>.name`. The flake discovers
module directories automatically. Enable a module in
`hosts/whiterabbit/configuration.bnix` or through tag membership and
`hosts/<host>/enabled-tags.bnix`, matching neighboring patterns. Diagnose
composition with `firn tag resolve whiterabbit`.

## Query and focused guides

Use:

```text
beagle-schema services.openssh.enable
beagle-schema --search ssh
firn schema explain <path-or-validator-error>
firn repo doctor
```

Read only the guide matching the current problem:

- `nixos-config:docs/schema-introspection.md` for options and types;
- `nixos-config:docs/renaming-option-paths.md` for option migrations;
- `nixos-config:docs/compiler-queries.md` for compiler facts;
- `nixos-config:docs/repair-pipeline.md` and
  `nixos-config:docs/diagnosing-schema-errors.md` for non-obvious validation;
- `nixos-config:docs/tags-composition.md` for tags;
- `nixos-config:docs/flake-inputs.md` for module inputs;
- `nixos-config:docs/platform-compatibility.md` for Darwin;
- `nixos-config:docs/bumping-inputs.md` for input bumps;
- `nixos-config:docs/importing-nix.md` for imported Nix;
- `nixos-config:docs/verification.md` for rung selection;
- `nixos-config:docs/crash-recovery.md` for a silent whiterabbit reboot.

## Verification and rebuild snapshot

`firn repo build` plus `firn repo validate` is the default loop.
`firn repo diff` re-emits targets and compares them with committed `.nix`.
When static validation cannot see a build-time issue, use:

```text
nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link
```

`firn rebuild` snapshots committed `HEAD`, validates that snapshot, builds it,
and switches the system. Its output names in-flight working-tree files excluded
from the snapshot and the exact revision being activated.

## Roll back one generation

Select an exact positive decimal generation already present and older than the
active one:

```text
firn rollback <generation>
```

Firn resolves the generation to one Nix store path containing an executable
`switch-to-configuration` and refuses before mutation if it cannot. On success,
run `firn host gen` and require `current:` to equal the requested generation.
After a failed activation, inspect the same state before retrying because the
profile may already have changed.
