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
  cfg = config.myConfig.modules.north-runtime-follow;
  username = config.myConfig.modules.users.username;
  description = "north-runtime-follow: every 20 s promote origin/main of north to the live runtime";
  retainDescription = "north-strategy-log-retain: hourly compress the decision log's closed hours and delete days past its retention";
in
{
  options.myConfig.modules.north-runtime-follow.enable = lib.mkEnableOption description // {
    default = config.myConfig.modules.agent-runtime-update.enable;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-runtime-follow = {
          Unit = {
            Description = description;
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "control.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "60min";
            SuccessExitStatus = "75";
            Environment = [
              "PATH=${unitPath}:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.bun
                  pkgs.coreutils
                  pkgs.git
                  pkgs.gnutar
                  pkgs.nix
                  pkgs.openssh
                  pkgs.rsync
                  pkgs.util-linux
                ]
              }"
            ];
            ExecStart = jobRun "north-runtime-follow" "${northBin}/north runtime update";
          };
        };
        services.north-strategy-log-retain = {
          Unit.Description = retainDescription;
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            Environment = [
              "PATH=${unitPath}:${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.zstd
                ]
              }"
            ];
            ExecStart = jobRun "north-strategy-log-retain" "${northBin}/north ops strategy log retain";
          };
        };
        timers.north-strategy-log-retain = {
          Unit.Description = retainDescription;
          Timer = {
            OnCalendar = "hourly";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
        timers.north-runtime-follow = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "2min";
            OnUnitInactiveSec = "20s";
            AccuracySec = "5s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
