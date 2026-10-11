{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.dbeaver.enable {
    "environment" = {
      "systemPackages" = [ pkgs.dbeaver-bin ];
    };
  };
  options."myConfig"."modules"."dbeaver"."enable" = lib.mkEnableOption "DBeaver database GUI";
}
