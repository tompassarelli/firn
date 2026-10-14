# Importing existing Nix

Use an existing NixOS module directly. Place it in its own module directory,
declare its typed enable option and guard the configuration with
`lib.mkIf config.myConfig.modules.<name>.enable`. The flake discovers module
directories automatically. Add composition metadata only when tags or
platform support are needed, then run `firn repo build` and `firn check`.
