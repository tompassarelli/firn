{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gtk;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkForce (
        if (config.stylix.polarity == "dark") then "prefer-dark" else "prefer-light"
      );
      gtk.enable = true;
      home.packages = [
        pkgs.gsettings-desktop-schemas
        pkgs.gtk3
      ];
      xdg.configFile = {
        "gtk-3.0/settings.ini".text = lib.mkForce ''
          [Settings]
          gtk-application-prefer-dark-theme=${if (config.stylix.polarity == "dark") then "1" else "0"}
          gtk-font-name=${hm.config.gtk.font.name} ${builtins.toString hm.config.gtk.font.size}
          gtk-theme-name=${hm.config.gtk.theme.name}

        '';
        "gtk-4.0/settings.ini".text = lib.mkForce ''
          [Settings]
          gtk-application-prefer-dark-theme=${if (config.stylix.polarity == "dark") then "1" else "0"}
          gtk-font-name=${hm.config.gtk.font.name} ${builtins.toString hm.config.gtk.font.size}
          gtk-theme-name=${hm.config.gtk.theme.name}

        '';
      };
    };
  };
  options.myConfig.modules.gtk.enable = lib.mkEnableOption "GTK theming configuration";
}
