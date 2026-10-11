{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.ffmpeg.enable {
    "environment" = {
      "systemPackages" = [ pkgs.ffmpeg ];
    };
  };
  options."myConfig"."modules"."ffmpeg"."enable" = lib.mkEnableOption "FFmpeg video processing";
}
