{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.eza.enable {
    "environment" = {
      "systemPackages" = [ pkgs.eza ];
    };
  };
  options."myConfig"."modules"."eza"."enable" = lib.mkEnableOption "Enable eza (modern ls replacement)";
}
