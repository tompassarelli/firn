{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.librewolf;
in
{
  options.myConfig.modules.librewolf = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set LibreWolf as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "librewolf";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.unstable.librewolf ];
    xdg.mime.defaultApplications = lib.mkIf cfg.default {
      "text/html" = "librewolf.desktop";
      "x-scheme-handler/about" = "librewolf.desktop";
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
      "x-scheme-handler/unknown" = "librewolf.desktop";
    };
  };
}
