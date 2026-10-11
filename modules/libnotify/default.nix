{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.libnotify.enable {
    "environment" = {
      "systemPackages" = [ pkgs.libnotify ];
    };
  };
  options."myConfig"."modules"."libnotify"."enable" = lib.mkEnableOption "libnotify notification client";
}
