{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.nautilus.enable {
    "environment" = {
      "systemPackages" = [ pkgs.nautilus ];
    };
    "services" = {
      "gvfs" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."nautilus"."enable" = lib.mkEnableOption "Nautilus file manager";
}
