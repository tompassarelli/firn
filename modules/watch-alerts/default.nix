{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.watch-alerts.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.watch-alerts.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.watch-alerts = {
        Unit = {
          Description = description;
          After = [ "network-online.target" ];
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "4min";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.python3 ]}"
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/model-watch --alerts-only";
        };
      };
      systemd.user.timers.watch-alerts = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = "*:0/5";
          AccuracySec = "30s";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "Deterministic location safety alerts")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
