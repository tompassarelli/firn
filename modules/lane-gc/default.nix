{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.lane-gc;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "lane-gc: hourly retire landed, clean, idle worktrees and branches in ~/code containers; report unlanded work";
in
{
  options.myConfig.modules.lane-gc.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services = {
          lane-gc = {
            Unit = {
              Description = description;
              OnFailure = [ "update-notify@%n.service" ];
            };
            Service = {
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "20min";
              Environment = [
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${
                  lib.makeBinPath [
                    pkgs.bun
                    pkgs.git
                    pkgs.openssh
                    pkgs.gh
                    pkgs.coreutils
                    pkgs.findutils
                    pkgs.python3
                  ]
                }"
              ];
              ExecStart = jobRun "lane-gc" "${homeDir}/.local/share/north/bin/lane-gc";
            };
          };
          lane-gc-remote = {
            Unit = {
              Description = "lane-gc: daily archive stale origin branches with verified liveness";
              OnFailure = [ "update-notify@%n.service" ];
            };
            Service = {
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "20min";
              Environment = [
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${
                  lib.makeBinPath [
                    pkgs.bun
                    pkgs.git
                    pkgs.openssh
                    pkgs.gh
                    pkgs.coreutils
                    pkgs.findutils
                    pkgs.python3
                  ]
                }"
              ];
              ExecStart = jobRun "lane-gc-remote" "${homeDir}/.local/share/north/bin/lane-gc --remote";
            };
          };
        };
        timers = {
          lane-gc = {
            Unit.Description = description;
            Timer = {
              OnBootSec = "10min";
              OnUnitActiveSec = "1h";
            };
            Install.WantedBy = [ "timers.target" ];
          };
          lane-gc-remote = {
            Unit.Description = "lane-gc: daily origin branch cleanup";
            Timer = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "30min";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
  };
}
