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
  config = lib.mkIf cfg.enable {
    hardware.graphics.enable = true;
    programs.obs-studio = {
      enable = true;
      plugins = [ pkgs.obs-studio-plugins.obs-vaapi ];
    };
  };
}
