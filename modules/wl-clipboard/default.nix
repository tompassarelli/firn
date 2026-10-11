{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.wl-clipboard.enable {
    "environment" = {
      "systemPackages" = [ pkgs.wl-clipboard ];
    };
  };
  options."myConfig"."modules"."wl-clipboard"."enable" = lib.mkEnableOption "Wayland clipboard utilities";
}
