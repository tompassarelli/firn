{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.obs-studio;
in
{
  options.myConfig.modules.obs-studio.enable = lib.mkEnableOption "OBS Studio screen recording";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.obs-studio ]; };
}
