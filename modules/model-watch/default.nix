{ config, lib, pkgs, jobRun, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.model-watch.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.model-watch.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.model-watch = {
        Unit = {
          Description = description;
          After = [ "agent-runtime-update.service" ];
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "10min";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.python3 ]}"
          ];
          ExecStart = jobRun "model-watch" "${homeDir}/.local/share/north/bin/model-watch";
        };
      };
      systemd.user.timers.model-watch = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = [ "08:00" "18:00" ];
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "Twice-daily ranked public watch digest")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
