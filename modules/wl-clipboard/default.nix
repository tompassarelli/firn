{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wl-clipboard;
in
{
  options.myConfig.modules.wl-clipboard.enable = lib.mkEnableOption "Wayland clipboard utilities";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.wl-clipboard ]; };
}
