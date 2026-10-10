{ config, lib, pkgs, ... }:

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
          ExecStart = "${homeDir}/.local/bin/model-watch";
        };
      };
      systemd.user.timers.model-watch = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = [ "02:10" "13:10" ];
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "Twice-daily public model release watch")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
