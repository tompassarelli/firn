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
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      gnome-themes-extra
    ];
  };
}
