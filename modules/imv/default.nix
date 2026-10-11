{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.imv.enable {
    "environment" = {
      "systemPackages" = [ pkgs.imv ];
    };
  };
  options."myConfig"."modules"."imv"."enable" = lib.mkEnableOption "imv image viewer";
}
