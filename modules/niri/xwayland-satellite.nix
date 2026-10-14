{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.niri;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.xwayland-satellite ]; };
}
