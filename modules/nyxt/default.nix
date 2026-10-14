{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nyxt;
in
{
  options.myConfig.modules.nyxt = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Nyxt as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "nyxt";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nyxt4 ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      xdg.configFile."nyxt/config.lisp".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/nyxt/config.lisp";
    };
    myConfig.modules.fuse.enable = lib.mkDefault true;
    programs.appimage.enable = true;
    xdg.mime.defaultApplications = lib.mkIf cfg.default {
      "text/html" = "nyxt.desktop";
      "x-scheme-handler/about" = "nyxt.desktop";
      "x-scheme-handler/http" = "nyxt.desktop";
      "x-scheme-handler/https" = "nyxt.desktop";
      "x-scheme-handler/unknown" = "nyxt.desktop";
    };
  };
}
