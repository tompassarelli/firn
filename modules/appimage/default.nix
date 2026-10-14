{ config, lib, ... }:
let
  cfg = config.myConfig.modules.appimage;
in
{
  options.myConfig.modules.appimage.enable =
    lib.mkEnableOption "AppImage support via appimage-run + binfmt";
  config = lib.mkIf cfg.enable {
    programs.appimage = {
      binfmt = true;
      enable = true;
    };
  };
}
