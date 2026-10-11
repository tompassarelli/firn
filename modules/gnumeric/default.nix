{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gnumeric.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gnumeric ];
    };
  };
  options."myConfig"."modules"."gnumeric"."enable" = lib.mkEnableOption "Gnumeric lightweight spreadsheet (xlsx/ods/csv viewer)";
}
