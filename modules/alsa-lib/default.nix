{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.alsa-lib;
in
{
  options.myConfig.modules.alsa-lib.enable = lib.mkEnableOption "alsa-lib";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.alsa-lib ]; };
}
