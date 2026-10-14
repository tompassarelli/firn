{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.mpv;
in
{
  options.myConfig.modules.mpv.enable = lib.mkEnableOption "mpv media player";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.mpv ]; };
}
