{ lib, modulesPath }:
lib.mapAttrs (
  name: _:
  let
    path = modulesPath + "/${name}/metadata.json";
  in
  {
    tags = [ ];
    optIn = [ ];
    overrides = { };
    supports = [ ];
    flakeInputs = { };
  }
  // lib.optionalAttrs (builtins.pathExists path) (builtins.fromJSON (builtins.readFile path))
) (lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir modulesPath))
