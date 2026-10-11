{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.mako.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "services" = {
            "mako" = {
              "enable" = true;
              "settings" = {
                "app-name=Spotify" = {
                  "invisible" = 1;
                };
                "app-name=kitty" = {
                  "default-timeout" = 0;
                };
                "default-timeout" = 0;
                "icons" = 0;
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."mako"."enable" = lib.mkEnableOption "Mako notification daemon";
}
