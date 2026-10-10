{ config, lib, pkgs, jobRun, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.lane-gc.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.lane-gc.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.lane-gc = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "20min";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/north/bin:${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.bun pkgs.git pkgs.openssh pkgs.gh pkgs.coreutils ]}"
          ];
          ExecStart = jobRun "lane-gc" "${homeDir}/.local/share/north/bin/lane-gc";
        };
      };
      systemd.user.timers.lane-gc = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnBootSec = "10min";
          OnUnitActiveSec = "1h";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "lane-gc: hourly retire landed, clean, idle worktrees and branches in ~/code containers; report unlanded work")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
