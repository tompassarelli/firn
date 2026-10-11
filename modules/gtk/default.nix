{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gtk.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = __clause_argument_3: {
          "dconf" = {
            "settings" = {
              "org/gnome/desktop/interface" = {
                "color-scheme" = lib.mkForce (if (config.stylix.polarity == "dark") then "prefer-dark" else "prefer-light");
              };
            };
          };
          "gtk" = {
            "enable" = true;
          };
          "home" = {
            "packages" = [ pkgs.gsettings-desktop-schemas pkgs.gtk3 ];
          };
          "xdg" = {
            "configFile" = {
              "gtk-3.0/settings.ini" = {
                "text" = lib.mkForce (((((((("[Settings]\ngtk-application-prefer-dark-theme=" + (if (config.stylix.polarity == "dark") then "1" else "0")) + "\ngtk-font-name=") + (((__clause_argument_3.config).gtk).font).name) + " ") + builtins.toString (((__clause_argument_3.config).gtk).font).size) + "\ngtk-theme-name=") + (((__clause_argument_3.config).gtk).theme).name) + "\n\n");
              };
              "gtk-4.0/settings.ini" = {
                "text" = lib.mkForce (((((((("[Settings]\ngtk-application-prefer-dark-theme=" + (if (config.stylix.polarity == "dark") then "1" else "0")) + "\ngtk-font-name=") + (((__clause_argument_3.config).gtk).font).name) + " ") + builtins.toString (((__clause_argument_3.config).gtk).font).size) + "\ngtk-theme-name=") + (((__clause_argument_3.config).gtk).theme).name) + "\n\n");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."gtk"."enable" = lib.mkEnableOption "GTK theming configuration";
}
