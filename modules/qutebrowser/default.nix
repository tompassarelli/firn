{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.qutebrowser;
in
{
  options.myConfig.modules.qutebrowser = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Qutebrowser as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "qutebrowser";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.qutebrowser ];
    xdg.mime.defaultApplications = lib.mkIf cfg.default {
      "text/html" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/about" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/http" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/https" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/unknown" = "org.qutebrowser.qutebrowser.desktop";
    };
  };
}
