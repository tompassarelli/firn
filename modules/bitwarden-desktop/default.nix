{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bitwarden-desktop;
in
{
  options.myConfig.modules.bitwarden-desktop.enable = lib.mkEnableOption "Bitwarden desktop app";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bitwarden-desktop ]; };
}
