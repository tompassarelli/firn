{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.nyxt.enable {
    "environment" = {
      "systemPackages" = [ pkgs.nyxt4 ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = hm: {
          "xdg" = {
            "configFile" = {
              "nyxt/config.lisp" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/code/nixos-config/dotfiles/nyxt/config.lisp");
              };
            };
          };
        };
      };
    };
    "myConfig" = {
      "modules" = {
        "fuse" = {
          "enable" = lib.mkDefault true;
        };
      };
    };
    "programs" = {
      "appimage" = {
        "enable" = true;
      };
    };
    "xdg" = {
      "mime" = {
        "defaultApplications" = lib.mkIf config.myConfig.modules.nyxt.default {
          "text/html" = "nyxt.desktop";
          "x-scheme-handler/about" = "nyxt.desktop";
          "x-scheme-handler/http" = "nyxt.desktop";
          "x-scheme-handler/https" = "nyxt.desktop";
          "x-scheme-handler/unknown" = "nyxt.desktop";
        };
      };
    };
  };
  options."myConfig"."modules"."nyxt"."default" = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Set Nyxt as the default browser via MIME types";
  };
  options."myConfig"."modules"."nyxt"."enable" = lib.mkEnableOption "Enable Nyxt browser";
}
