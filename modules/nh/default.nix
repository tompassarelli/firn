{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.nh.enable {
    "environment" = {
      "systemPackages" = [ pkgs.nh ];
    };
  };
  options."myConfig"."modules"."nh"."enable" = lib.mkEnableOption "Nix helper (nicer nixos-rebuild output, generation diff, search, clean)";
}
