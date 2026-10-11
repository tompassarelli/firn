{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.discord.enable {
    "environment" = {
      "systemPackages" = [ pkgs.discord ];
    };
  };
  options."myConfig"."modules"."discord"."enable" = lib.mkEnableOption "Discord chat client";
}
