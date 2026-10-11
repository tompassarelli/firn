{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.unzip.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unzip ];
    };
  };
  options."myConfig"."modules"."unzip"."enable" = lib.mkEnableOption "unzip archive tool";
}
