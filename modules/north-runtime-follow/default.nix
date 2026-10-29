{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-runtime-follow;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-runtime-follow: every 2 min promote origin/main of north to the live runtime";
in
{
  options.myConfig.modules.north-runtime-follow.enable = lib.mkEnableOption description // {
    default = config.myConfig.modules.agent-runtime-update.enable;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-runtime-follow = {
          Unit.Description = description;
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            SuccessExitStatus = "75";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
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
            OnUnitInactiveSec = "2min";
            AccuracySec = "15s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
