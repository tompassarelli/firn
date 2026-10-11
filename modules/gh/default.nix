{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gh.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gh ];
    };
  };
  options."myConfig"."modules"."gh"."enable" = lib.mkEnableOption "GitHub CLI";
}
