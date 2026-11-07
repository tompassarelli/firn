{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.lane-gc;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "lane-gc: hourly retire landed, clean, idle worktrees and branches and every origin branch in ~/code containers; report unlanded work and box unlanded origin branches";
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
                "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
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
              ExecStart = jobRun "lane-gc" "${northBin}/north lane gc";
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
