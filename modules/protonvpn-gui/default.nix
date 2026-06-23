{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.protonvpn-gui.enable = lib.mkEnableOption "ProtonVPN GUI client";
  config = lib.mkIf config.myConfig.modules.protonvpn-gui.enable {
    environment.systemPackages = with pkgs; [ proton-vpn ];
  };
}
