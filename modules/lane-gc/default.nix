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
  cfg = config.myConfig.modules.lane-gc;
  username = config.myConfig.modules.users.username;
  description = "lane-gc: hourly reclaim scratch in the temporary directory idle 3 h and held by no process, retire landed, clean, idle worktrees and branches and every origin branch in ~/code containers; report unlanded work and box unlanded origin branches";
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
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Slice = "agent.slice";
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "20min";
              Environment = [
                "PATH=${unitPath}:${
                  lib.makeBinPath [
                    pkgs.git
                    pkgs.openssh
                    pkgs.gh
                    pkgs.coreutils
                    pkgs.findutils
                    pkgs.python3
                  ]
                }"
              ];
              ExecStart = [
                "-${jobRun "lane-gc-scratch" "${northBin}/north lane reclaim --only scratch --idle-hours 3"}"
                (jobRun "lane-gc" "${northBin}/north lane gc")
              ];
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
        };
      };
    };
  };
}
