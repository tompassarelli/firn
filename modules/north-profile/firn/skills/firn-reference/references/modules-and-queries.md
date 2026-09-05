# Modules and compiler queries

## Source pipeline and rationale

```text
*.bnix --(firn repo build)--> *.nix --(firn rebuild)--> system
```

The flake reads the Git tree, so new source and generated targets must be
tracked. Beagle itself is documented by `beagle-authoring-distilled`.

The configuration compiler owns syntax and schema. Follow a nearby module
rather than designing a new enablement convention for a package.
The example below is schematic, not a complete file to paste: replace its
placeholders and query the current compiler before relying on the syntax.

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

Package lookup must use the consumer's selected nixpkgs when identity/version
matters; an ambient registry lookup may resolve a different revision.
Module existence is not enablement, and enablement is not proof a switch ran.

## Query by question

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

These are alternative routes. Loading every guide or invoking doctor without a
specific suspicion expands work without deciding the installation.
