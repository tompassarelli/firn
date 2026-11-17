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
in
{
  options.myConfig.modules.north-runtime-follow.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-runtime-follow = {
          Unit = {
            Description = description;
            ConditionPathExists = "!%h/.local/state/north/channel/stable";
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
