{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.myConfig.modules.zen-browser;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
    ];
    xdg.mime.defaultApplications = lib.mkIf cfg.default {
      "text/html" = "zen.desktop";
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
      "x-scheme-handler/about" = "zen.desktop";
      "x-scheme-handler/unknown" = "zen.desktop";
    };
  };
}
