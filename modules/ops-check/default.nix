{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.ops-check;
  username = config.myConfig.modules.users.username;
  environment = [
    "PATH=${unitPath}:${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.git
        pkgs.openssh
      ]
    }"
  ];
  unit = name: description: arguments: {
    Unit = {
      Description = description;
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Slice = "control.slice";
      Type = "oneshot";
      Nice = 10;
      TimeoutStartSec = "5min";
      Environment = environment;
      ExecStart = jobRun name "${northBin}/north ops check${arguments}";
    };
  };
in
{
  options.myConfig.modules.ops-check = {
    enable = lib.mkEnableOption "ops-check: every 5 min run north ops check, which leaves a heartbeat on Nexus and reads it from every other host as the dead-man check";
    synthetic = lib.mkEnableOption "ops-check-synthetic: weekly north ops check --synthetic, which drills the phone and proxy alert path end to end";
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services = {
          ops-check = unit "ops-check" "north ops check: core expectations, heartbeat and dead-man check" "";
        }
        // lib.optionalAttrs cfg.synthetic {
          ops-check-synthetic =
            unit "ops-check-synthetic" "north ops check --synthetic: weekly drill of the breach alert path"
              " --synthetic";
        };
        timers = {
          ops-check = {
            Unit.Description = "north ops check every 5 minutes";
            Timer = {
              OnBootSec = "2min";
              OnCalendar = "*-*-* *:00/5:00";
              AccuracySec = "15s";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        }
        // lib.optionalAttrs cfg.synthetic {
          ops-check-synthetic = {
            Unit.Description = "north ops check --synthetic weekly";
            Timer = {
              OnCalendar = "Mon *-*-* 09:30:00";
              Persistent = true;
              AccuracySec = "1min";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
  };
}
