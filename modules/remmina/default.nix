{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.remmina.enable {
    "environment" = {
      "systemPackages" = [ pkgs.remmina ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "xdg" = {
            "configFile" = {
              "autostart/remmina-applet.desktop" = {
                "text" = "[Desktop Entry]\nHidden=true\n\n";
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."remmina"."enable" = lib.mkEnableOption "Remmina remote desktop client";
}
