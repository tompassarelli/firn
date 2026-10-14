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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.mpv ]; };
  options.myConfig.modules.mpv.enable = lib.mkEnableOption "mpv media player";
}
