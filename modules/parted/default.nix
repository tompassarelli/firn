{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.parted.enable {
    "environment" = {
      "systemPackages" = [ pkgs.parted ];
    };
  };
  options."myConfig"."modules"."parted"."enable" = lib.mkEnableOption "disk partitioning tool";
}
