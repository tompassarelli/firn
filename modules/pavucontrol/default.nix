{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.pavucontrol.enable {
    "environment" = {
      "systemPackages" = [ pkgs.pavucontrol ];
    };
  };
  options."myConfig"."modules"."pavucontrol"."enable" = lib.mkEnableOption "PulseAudio volume control";
}
