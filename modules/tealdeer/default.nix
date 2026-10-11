{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.tealdeer.enable {
    "environment" = {
      "systemPackages" = [ pkgs.tealdeer ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = __clause_argument_0: {
          "xdg" = {
            "configFile" = {
              "tealdeer/config.toml" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/tealdeer/config.toml");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."tealdeer"."enable" = lib.mkEnableOption "Enable tealdeer (tldr client)";
}
