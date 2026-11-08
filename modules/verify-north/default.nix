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
  cfg = config.myConfig.modules.verify-north;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "verify-north: daily unattended end-to-end run of the promoted north runtime: a worker takes a brief, safe-push queues its change and the lander lands it";
in
{
  options.myConfig.modules.verify-north.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.verify-north = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            WorkingDirectory = "${homeDir}/code/south/main";
            Environment = [
              "PATH=${unitPath}:${
                lib.makeBinPath [
                  pkgs.tmux
                  pkgs.git
                  pkgs.coreutils
                ]
              }"
            ];
            ExecStart = jobRun "verify-north" "${northBin}/verify-north --north north";
          };
        };
        timers.verify-north = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
