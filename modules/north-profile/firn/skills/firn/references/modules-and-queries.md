# Modules and option queries

Create `modules/<name>/default.nix`, following a nearby module's typed options
and `lib.mkIf cfg.enable` configuration. Confirm the package in the selected
nixpkgs input, rather than an ambient registry revision. Dynamic imports
discover module directories; track every new source before committed builds.

A module's `metadata.json` declares tag membership, opt-in tags, platform
support and flake-input requirements. A host's `tags.json` declares its
composition and direct module choices. Change Nix for service configuration
and metadata for composition. Run `firn repo build` after metadata edits,
then `firn check`. Use `firn tag resolve <host>` to explain enablement.

`firn schema explain <path>` inspects NixOS options. Search Nix references
with `rg -n '<path>' modules hosts`. Read only the guide matching the issue:

- `nixos-config:docs/schema-introspection.md` for types and declarations;
- `nixos-config:docs/renaming-option-paths.md` for coordinated renames;
- `nixos-config:docs/TAGS.md` for composition;
- `nixos-config:docs/flake-inputs.md` for input requirements;
- `nixos-config:docs/platform-compatibility.md` for Darwin;
- `nixos-config:docs/bumping-inputs.md` for input updates;
- `nixos-config:docs/verification.md` for checking and switching;
- `nixos-config:docs/crash-recovery.md` for a silent host reboot.

Module existence, enablement and a completed switch are separate observations.
