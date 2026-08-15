{ config, lib, pkgs, ... }:

((username: {
  config = lib.mkIf config.myConfig.modules.niri.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.swayidle = {
        Unit = {
          Description = "Idle manager for Wayland";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 601 'niri msg action power-off-monitors' timeout 600 'swaylock -f' before-sleep 'swaylock -f'";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.username)
