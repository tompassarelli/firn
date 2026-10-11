{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.protonvpn-gui.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.proton-vpn ];
    };
  };
  options."myConfig"."modules"."protonvpn-gui"."enable" = lib.mkEnableOption "ProtonVPN GUI client";
}
