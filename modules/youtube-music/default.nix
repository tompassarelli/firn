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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.youtube-music ]; };
  options.myConfig.modules.youtube-music.enable = lib.mkEnableOption "YouTube Music client";
}
