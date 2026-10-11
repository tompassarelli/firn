{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.qutebrowser.enable {
    "environment" = {
      "systemPackages" = [ pkgs.qutebrowser ];
    };
    "xdg" = {
      "mime" = {
        "defaultApplications" = lib.mkIf config.myConfig.modules.qutebrowser.default {
          "text/html" = "org.qutebrowser.qutebrowser.desktop";
          "x-scheme-handler/about" = "org.qutebrowser.qutebrowser.desktop";
          "x-scheme-handler/http" = "org.qutebrowser.qutebrowser.desktop";
          "x-scheme-handler/https" = "org.qutebrowser.qutebrowser.desktop";
          "x-scheme-handler/unknown" = "org.qutebrowser.qutebrowser.desktop";
        };
      };
    };
  };
  options."myConfig"."modules"."qutebrowser"."default" = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Set Qutebrowser as the default browser via MIME types";
  };
  options."myConfig"."modules"."qutebrowser"."enable" = lib.mkEnableOption "Enable Qutebrowser";
}
