{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.spotify.enable {
    "environment" = {
      "systemPackages" = [ pkgs.spotify ];
    };
  };
  options."myConfig"."modules"."spotify"."enable" = lib.mkEnableOption "Spotify TUI player";
}
