{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.mpv.enable {
    "environment" = {
      "systemPackages" = [ pkgs.mpv ];
    };
  };
  options."myConfig"."modules"."mpv"."enable" = lib.mkEnableOption "mpv media player";
}
