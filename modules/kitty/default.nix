{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.kitty.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "programs" = {
            "kitty" = {
              "enable" = true;
              "settings" = {
                "tab_bar_edge" = "top";
                "tab_bar_style" = "powerline";
                "window_padding_width" = "2 0 0 3";
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."kitty"."enable" = lib.mkEnableOption "Kitty terminal configuration";
}
