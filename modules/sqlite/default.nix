{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.sqlite.enable {
    "environment" = {
      "systemPackages" = [ pkgs.sqlite ];
    };
  };
  options."myConfig"."modules"."sqlite"."enable" = lib.mkEnableOption "SQLite database";
}
