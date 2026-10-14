{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.remmina;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.remmina ];
    home-manager.users.${config.myConfig.modules.users.username}.xdg.configFile."autostart/remmina-applet.desktop".text =
      ''
        [Desktop Entry]
        Hidden=true

      '';
  };
  options.myConfig.modules.remmina.enable = lib.mkEnableOption "Remmina remote desktop client";
}
