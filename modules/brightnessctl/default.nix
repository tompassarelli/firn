{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.brightnessctl.enable {
    "environment" = {
      "systemPackages" = [ pkgs.brightnessctl ];
    };
  };
  options."myConfig"."modules"."brightnessctl"."enable" = lib.mkEnableOption "screen brightness control";
}
