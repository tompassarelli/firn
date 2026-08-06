{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.spaces.enable = lib.mkEnableOption "spaces — two-level activity layer over niri workspaces (spaced daemon + CLI)";
  config = lib.mkIf config.myConfig.modules.spaces.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.spaces-daemon = {
        Unit = {
          Description = "spaces daemon (niri activity layer)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "%h/code/nixos-config/dotfiles/bin/spaces daemon";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
      xdg.configFile."spaces/spaces.edn".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/spaces/spaces.edn";
    });
  };
}
