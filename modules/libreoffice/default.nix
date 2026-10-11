{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.libreoffice.enable {
    "environment" = {
      "systemPackages" = [ pkgs.libreoffice-fresh ];
    };
  };
  options."myConfig"."modules"."libreoffice"."enable" = lib.mkEnableOption "Enable LibreOffice office suite";
}
