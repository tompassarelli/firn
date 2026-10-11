{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.fwupd.enable {
    "environment" = {
      "systemPackages" = [ pkgs.fwupd ];
    };
  };
  options."myConfig"."modules"."fwupd"."enable" = lib.mkEnableOption "fwupd firmware updater";
}
