{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gnome-screenshot;
in
{
  options.myConfig.modules.gnome-screenshot.enable = lib.mkEnableOption "GNOME Screenshot tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gnome-screenshot ]; };
}
