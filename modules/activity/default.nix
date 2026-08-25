{ config, firnLaunchers, lib, pkgs, ... }:

((username: {
  tags = [ desktop ];
  options.myConfig.modules.activity.enable = lib.mkEnableOption "activity — activities own workspaces: two-level layer over niri (daemon + CLI)";
  config = lib.mkIf config.myConfig.modules.activity.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.activity-daemon = {
        Unit = {
          Description = "activity daemon (niri activity layer)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${firnLaunchers}/bin/activity daemon";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
      xdg.configFile."activity/activities.edn".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/activity/activities.edn";
    });
  };
}) config.myConfig.modules.users.username)
