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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ffmpeg ]; };
  options.myConfig.modules.ffmpeg.enable = lib.mkEnableOption "FFmpeg video processing";
}
