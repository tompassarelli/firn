{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.starship.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "programs" = {
            "starship" = {
              "enable" = true;
              "enableFishIntegration" = true;
              "settings" = {
                "add_newline" = false;
                "character" = {
                  "error_symbol" = "[λ](bold red)";
                  "success_symbol" = "[λ](bold green)";
                  "vimcmd_symbol" = "[λ](bold green)";
                };
                "directory" = {
                  "truncate_to_repo" = false;
                  "truncation_length" = 0;
                };
                "format" = lib.concatStrings [ "$directory" "$character" ];
                "hostname" = {
                  "disabled" = true;
                };
                "username" = {
                  "disabled" = true;
                };
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."starship"."enable" = lib.mkEnableOption "starship prompt";
}
