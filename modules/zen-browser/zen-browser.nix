{ config, lib, pkgs, inputs, ... }:

{
  config = lib.mkIf config.myConfig.modules.zen-browser.enable {
    environment.systemPackages = [
      (inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}").default
    ];
    xdg.mime.defaultApplications = lib.mkIf config.myConfig.modules.zen-browser.default {
      "text/html" = "zen.desktop";
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
      "x-scheme-handler/about" = "zen.desktop";
      "x-scheme-handler/unknown" = "zen.desktop";
    };
  };
}
