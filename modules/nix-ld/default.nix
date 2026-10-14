{ config, lib, ... }:
let
  cfg = config.myConfig.modules.nix-ld;
in
{
  config = lib.mkIf cfg.enable { programs.nix-ld.enable = true; };
  options.myConfig.modules.nix-ld.enable = lib.mkEnableOption "nix-ld dynamic library shim";
}
