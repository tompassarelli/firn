{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.tealdeer.enable {
    "environment" = {
      "systemPackages" = [ pkgs.tealdeer ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = hm: {
          "xdg" = {
            "configFile" = {
              "tealdeer/config.toml" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/code/nixos-config/dotfiles/tealdeer/config.toml");
              };
            };
          };
        };
      };
    };
  };
  options.myConfig.modules.tealdeer.enable = lib.mkEnableOption "tealdeer";
}
