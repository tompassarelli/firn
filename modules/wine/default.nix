{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.wine.enable {
    "environment" = {
      "systemPackages" = [ pkgs.wineWowPackages.unstable pkgs.unstable.winetricks ];
    };
  };
  options."myConfig"."modules"."wine"."enable" = lib.mkEnableOption "Wine (unstable, 32+64-bit)";
}
