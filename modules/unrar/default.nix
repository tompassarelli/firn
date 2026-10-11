{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.unrar.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unrar ];
    };
  };
  options."myConfig"."modules"."unrar"."enable" = lib.mkEnableOption "unrar archive tool";
}
