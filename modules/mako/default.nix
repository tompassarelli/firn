{ config, lib, ... }:
let
  cfg = config.myConfig.modules.mako;
in
{
  options.myConfig.modules.mako.enable = lib.mkEnableOption "Mako notification daemon";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username}.services.mako = {
      enable = true;
      settings = {
        "app-name=Spotify".invisible = 1;
        "app-name=kitty".default-timeout = 0;
        default-timeout = 0;
        icons = 0;
      };
    };
  };
}
