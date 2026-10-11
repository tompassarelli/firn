{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.fastfetch.enable {
    "environment" = {
      "systemPackages" = [ pkgs.fastfetch ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = __clause_argument_0: {
          "xdg" = {
            "configFile" = {
              "fastfetch/config.jsonc" = {
                "source" = (((__clause_argument_0.config).lib).file).mkOutOfStoreSymlink (("" + ((__clause_argument_0.config).home).homeDirectory) + "/code/nixos-config/dotfiles/fastfetch/config.jsonc");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."fastfetch"."enable" = lib.mkEnableOption "Enable fastfetch system info display";
}
