{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.sqlcmd.enable {
    "environment" = {
      "systemPackages" = [ pkgs.sqlcmd ];
    };
  };
  options."myConfig"."modules"."sqlcmd"."enable" = lib.mkEnableOption "sqlcmd for Microsoft SQL Server";
}
