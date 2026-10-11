{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gimp.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gimp ];
    };
  };
  options."myConfig"."modules"."gimp"."enable" = lib.mkEnableOption "GIMP image editor";
}
