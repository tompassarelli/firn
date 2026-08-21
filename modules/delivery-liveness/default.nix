{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.delivery-liveness.enable = lib.mkEnableOption "periodically build the committed Firn toplevel without switching";
  config = lib.mkIf config.myConfig.modules.delivery-liveness.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.firn-delivery-liveness = {
        Unit = {
          Description = "Firn delivery liveness floor (non-switching)";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.homeDirectory}/.local/bin/firn-liveness-floor";
          TimeoutStartSec = "30m";
        };
      };
      systemd.user.timers.firn-delivery-liveness = {
        Unit = {
          Description = "Run Firn delivery liveness floor";
        };
        Timer = {
          OnCalendar = "*:0/30";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.username)
