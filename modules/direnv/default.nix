{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.direnv.enable {
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "programs" = {
            "direnv" = {
              "enable" = true;
              "nix-direnv" = {
                "enable" = true;
              };
            };
          };
        };
      };
    };
    "programs" = {
      "direnv" = {
        "enable" = true;
        "nix-direnv" = {
          "enable" = true;
        };
      };
    };
  };
  options."myConfig"."modules"."direnv"."enable" = lib.mkEnableOption "direnv for automatic dev shell activation";
}
