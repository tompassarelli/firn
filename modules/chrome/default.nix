{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.chrome.enable {
    "environment" = {
      "systemPackages" = [ pkgs.google-chrome ];
    };
    "xdg" = {
      "mime" = {
        "defaultApplications" = lib.mkIf config.myConfig.modules.chrome.default {
          "text/html" = "google-chrome.desktop";
          "x-scheme-handler/about" = "google-chrome.desktop";
          "x-scheme-handler/http" = "google-chrome.desktop";
          "x-scheme-handler/https" = "google-chrome.desktop";
          "x-scheme-handler/unknown" = "google-chrome.desktop";
        };
      };
    };
  };
  options."myConfig"."modules"."chrome"."default" = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Set Chrome as the default browser via MIME types";
  };
  options."myConfig"."modules"."chrome"."enable" = lib.mkEnableOption "Enable Google Chrome browser";
}
