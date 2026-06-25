{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.chrome.enable {
    environment.systemPackages = with pkgs; [ google-chrome ];
    xdg.mime.defaultApplications = lib.mkIf config.myConfig.modules.chrome.default {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
    };
  };
}
