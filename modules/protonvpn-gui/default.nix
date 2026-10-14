{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.protonvpn-gui;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.proton-vpn ]; };
  options.myConfig.modules.protonvpn-gui.enable = lib.mkEnableOption "ProtonVPN GUI client";
}
