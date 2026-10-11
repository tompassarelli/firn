{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gnome-screenshot.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gnome-screenshot ];
    };
  };
  options."myConfig"."modules"."gnome-screenshot"."enable" = lib.mkEnableOption "GNOME Screenshot tool";
}
