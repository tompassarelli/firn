{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.appimage.enable {
    "programs" = {
      "appimage" = {
        "binfmt" = true;
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."appimage"."enable" = lib.mkEnableOption "AppImage support via appimage-run + binfmt";
}
