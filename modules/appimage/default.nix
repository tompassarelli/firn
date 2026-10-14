{ config, lib, ... }:
let
  cfg = config.myConfig.modules.appimage;
in
{
  config = lib.mkIf cfg.enable {
    programs.appimage = {
      binfmt = true;
      enable = true;
    };
  };
  options.myConfig.modules.appimage.enable =
    lib.mkEnableOption "AppImage support via appimage-run + binfmt";
}
