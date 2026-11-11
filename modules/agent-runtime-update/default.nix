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
  cfg = config.myConfig.modules.agent-runtime-update;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.agent-runtime-update.enable =
    lib.mkEnableOption "Twice-daily agent runtime updates";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.agent-runtime-update = {
          Unit = {
            Description = "Twice-daily agent runtime updates";
            OnFailure = [ "update-notify@%N.service" ];
            ConditionPathExists = "!%h/.local/state/north/channel/stable";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            TimeoutStartSec = "4h";
            Environment = [
              "PATH=${unitPath}:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.bun
                  pkgs.coreutils
                  pkgs.curl
                  pkgs.git
                  pkgs.gh
                  pkgs.nix
                  pkgs.python3
                  pkgs.zstd
                  pkgs.gnutar
                  pkgs.gzip
                  pkgs.util-linux
                  pkgs.libnotify
                  pkgs.systemd
                ]
              }"
            ];
            ExecStart = jobRun "agent-runtime-update" "${northBin}/north runtime agents";
          };
        };
        timers.agent-runtime-update = {
          Unit.Description = "Twice-daily agent runtime updates";
          Timer = {
            OnCalendar = [
              "02:00"
              "13:00"
            ];
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
