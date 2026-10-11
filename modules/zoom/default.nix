{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.zoom.enable {
    "environment" = {
      "systemPackages" = [ pkgs.zoom-us ];
    };
  };
  options."myConfig"."modules"."zoom"."enable" = lib.mkEnableOption "Zoom video conferencing";
}
