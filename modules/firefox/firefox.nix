{ config, lib, ... }:
let
  cfg = config.myConfig.modules.firefox;
in
{
  config = lib.mkIf cfg.enable {
    programs.firefox.enable = true;
    xdg.mime.defaultApplications = lib.mkIf config.myConfig.modules.firefox.default {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };
}
