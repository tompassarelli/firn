{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.imagemagick;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.imagemagick ]; };
  options.myConfig.modules.imagemagick.enable = lib.mkEnableOption "ImageMagick image processing";
}
