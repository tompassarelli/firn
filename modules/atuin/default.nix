{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.atuin.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "programs" = {
            "atuin" = {
              "enable" = true;
              "enableFishIntegration" = true;
              "settings" = {
                "auto_sync" = true;
                "search_mode" = "fuzzy";
                "sync_frequency" = "5m";
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."atuin"."enable" = lib.mkEnableOption "atuin shell history sync";
}
