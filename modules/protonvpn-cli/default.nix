{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.protonvpn-cli;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.protonvpn-cli ]; };
  options.myConfig.modules.protonvpn-cli.enable = lib.mkEnableOption "ProtonVPN CLI client";
}
