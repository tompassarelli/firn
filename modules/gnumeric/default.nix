{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.gnumeric.enable = lib.mkEnableOption "Gnumeric lightweight spreadsheet (xlsx/ods/csv viewer)";
  config = lib.mkIf config.myConfig.modules.gnumeric.enable {
    environment.systemPackages = with pkgs; [ gnumeric ];
  };
}
