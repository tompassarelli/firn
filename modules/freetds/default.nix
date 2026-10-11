{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.freetds.enable {
    "environment" = {
      "systemPackages" = [ pkgs.freetds ];
    };
  };
  options."myConfig"."modules"."freetds"."enable" = lib.mkEnableOption "FreeTDS (TDS protocol library for MSSQL)";
}
