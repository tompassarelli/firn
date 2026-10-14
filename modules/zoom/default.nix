{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.zoom;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.zoom-us ]; };
  options.myConfig.modules.zoom.enable = lib.mkEnableOption "Zoom video conferencing";
}
