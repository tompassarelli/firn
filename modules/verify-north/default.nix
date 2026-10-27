{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.verify-north;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "verify-north: daily unattended end-to-end run of the promoted north runtime through the fleet TUI and CLI";
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
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            WorkingDirectory = "${homeDir}/code/south/main";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${
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
