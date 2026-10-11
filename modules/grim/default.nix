{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.grim.enable {
    "environment" = {
      "systemPackages" = [ pkgs.grim ];
    };
  };
  options."myConfig"."modules"."grim"."enable" = lib.mkEnableOption "Grim screenshot tool";
}
