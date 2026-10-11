{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.kooha.enable {
    "environment" = {
      "systemPackages" = [ pkgs.kooha ];
    };
  };
  options."myConfig"."modules"."kooha"."enable" = lib.mkEnableOption "Kooha screen recorder";
}
