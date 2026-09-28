{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.protonup-qt.enable = lib.mkEnableOption "ProtonUp-Qt compatibility tool manager";
  config = lib.mkIf config.myConfig.modules.protonup-qt.enable {
    environment.systemPackages = with pkgs; [ protonup-qt ];
  };
}
