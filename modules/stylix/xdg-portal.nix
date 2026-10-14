{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.stylix;
in
{
  config = lib.mkIf cfg.enable {
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
        pkgs.kdePackages.xdg-desktop-portal-kde
      ];
    };
  };
}
