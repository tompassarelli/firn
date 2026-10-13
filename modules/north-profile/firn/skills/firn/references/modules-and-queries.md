# Modules and compiler queries

## Source pipeline and rationale

```text
*.gal --(firn repo build)--> *.nix --(firn rebuild)--> system
```

The flake reads the Git tree, so new source and generated targets must be
tracked. `galileo help syntax` prints the language card.

The configuration compiler owns syntax and schema. Follow a nearby module
rather than designing a new enablement convention for a package.
The example below is schematic, not a complete file to paste: replace its
placeholders and run `galileo check` before relying on the syntax.

## Add a module

Create `modules/<name>/default.gal`, following an existing simple module:

```text
use firn/tags

tags: cli-tools

config
  "environment"
    "systemPackages": [pkgs.<name>]
"enable": "..."
```

Firn lowers `modules/<name>/default.gal` to the `<name>` Module fact.
Module sources imply `nix module` and the standard `config, lib, pkgs, ...`
arguments. An implicit `config` block uses the module's enable guard; an
explicit guard or differing argument list retains its declared behavior.
`tags:` emits the same facts as `<name> is tagged <tag>`, including tags
declared elsewhere. `enable:` keeps a custom description with unquoted option
attributes; `"enable":` keeps quoted attributes. Without a declared enable
option, an implicit default module receives the standard option described by
its name. Explicit module and file declarations remain overrides.

Then run:

```text
firn repo build
firn repo validate
git add modules/<name>/default.gal modules/<name>/default.nix
```

Confirm a package first with `nix eval nixpkgs#<name>.name`. The flake discovers
module directories automatically. Enable a module in
`hosts/whiterabbit/configuration.gal` or through tag membership and
`hosts/<host>/_generated-enables.gal`, matching neighboring patterns. Diagnose
composition with `firn tag resolve whiterabbit`.

Package lookup must use the consumer's selected nixpkgs when identity/version
matters; an ambient registry lookup may resolve a different revision.
Module existence is not enablement, and enablement is not proof a switch ran.

## Query by question

Use:

```text
galileo schema explain services.openssh.enable
galileo refs myConfig.modules.<name>.enable
galileo query 'all ?m where ?m is a Module' --json
galileo check
firn schema explain <path-or-validator-error>
```

Read only the guide matching the current problem:

- `nixos-config:docs/schema-introspection.md` for options and types;
- `nixos-config:docs/renaming-option-paths.md` for option migrations;
- `nixos-config:docs/compiler-queries.md` for compiler facts;
- `nixos-config:docs/diagnosing-schema-errors.md` for non-obvious validation;
- `nixos-config:docs/tags-composition.md` for tags;
- `nixos-config:docs/flake-inputs.md` for module inputs;
- `nixos-config:docs/platform-compatibility.md` for Darwin;
- `nixos-config:docs/bumping-inputs.md` for input bumps;
- `nixos-config:docs/importing-nix.md` for imported Nix;
- `nixos-config:docs/verification.md` for rung selection;
- `nixos-config:docs/crash-recovery.md` for a silent whiterabbit reboot.

These are alternative routes. Loading every guide or invoking doctor without a
specific suspicion expands work without deciding the installation.
