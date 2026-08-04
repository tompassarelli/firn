{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.kooha.enable = lib.mkEnableOption "Kooha screen recorder";
  config = lib.mkIf config.myConfig.modules.kooha.enable {
    environment.systemPackages = [ pkgs.kooha ];
  };
}
