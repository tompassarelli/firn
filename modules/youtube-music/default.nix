{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.youtube-music.enable {
    "environment" = {
      "systemPackages" = [ pkgs.youtube-music ];
    };
  };
  options."myConfig"."modules"."youtube-music"."enable" = lib.mkEnableOption "YouTube Music client";
}
