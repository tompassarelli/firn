{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.chrome;
in
{
  options.myConfig.modules.chrome = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Chrome as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "chrome";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.google-chrome ];
    xdg.mime.defaultApplications = lib.mkIf cfg.default {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
    };
  };
}
