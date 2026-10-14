{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.youtube-music;
in
{
  options.myConfig.modules.youtube-music.enable = lib.mkEnableOption "YouTube Music client";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.youtube-music ]; };
}
