{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.libnotify;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libnotify ]; };
  options.myConfig.modules.libnotify.enable = lib.mkEnableOption "libnotify notification client";
}
