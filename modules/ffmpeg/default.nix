{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ffmpeg;
in
{
  options.myConfig.modules.ffmpeg.enable = lib.mkEnableOption "FFmpeg video processing";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ffmpeg ]; };
}
