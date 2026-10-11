{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.swaylock.enable {
    "environment" = {
      "systemPackages" = [ pkgs.swaylock ];
    };
  };
  options."myConfig"."modules"."swaylock"."enable" = lib.mkEnableOption "swaylock screen locker";
}
