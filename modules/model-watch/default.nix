{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.model-watch;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Twice-daily ranked public watch digest";
in
{
  options.myConfig.modules.model-watch.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services = {
          model-watch = {
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
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                  lib.makeBinPath [ pkgs.python3 ]
                }"
              ];
              ExecStart = jobRun "model-watch" "${northBin}/model-watch";
            };
          };
          cross-project-scan = {
            Unit = {
              Description = "Daily cross-project overlap scan for Plato";
              OnFailure = [ "update-notify@%n.service" ];
            };
            Service = {
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "20min";
              Environment = [
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin"
              ];
              ExecStart = jobRun "cross-project-scan" "${northBin}/cross-project-scan";
            };
          };
          skill-prune = {
            Unit = {
              Description = "Weekly skill and lesson prune";
              OnFailure = [ "update-notify@%n.service" ];
            };
            Service = {
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "100min";
              Environment = [
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${
                  lib.makeBinPath [ pkgs.python3 ]
                }"
              ];
              ExecStart = jobRun "skill-prune" "${northBin}/skill-prune";
            };
          };
        };
        timers = {
          model-watch = {
            Unit.Description = description;
            Timer = {
              OnCalendar = [
                "08:00"
                "18:00"
              ];
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
          cross-project-scan = {
            Unit.Description = "Daily cross-project overlap scan for Plato";
            Timer = {
              OnCalendar = [ "07:30" ];
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
          skill-prune = {
            Unit.Description = "Weekly skill and lesson prune";
            Timer = {
              OnCalendar = [ "Sun 09:00" ];
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
  };
}
