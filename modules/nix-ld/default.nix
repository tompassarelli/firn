{ config, lib, ... }:
let
  cfg = config.myConfig.modules.nix-ld;
in
{
  options.myConfig.modules.nix-ld.enable = lib.mkEnableOption "nix-ld dynamic library shim";
  config = lib.mkIf cfg.enable { programs.nix-ld.enable = true; };
}
