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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bitwarden-desktop ]; };
  options.myConfig.modules.bitwarden-desktop.enable = lib.mkEnableOption "Bitwarden desktop app";
}
