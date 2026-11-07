{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.cross-project-scan;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Daily cross-project overlap scan for Plato";
in
{
  options.myConfig.modules.cross-project-scan.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.cross-project-scan = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "20min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${lib.makeBinPath [ pkgs.git ]}"
            ];
            ExecStart = jobRun "cross-project-scan" "${northBin}/north cross-project-scan";
          };
        };
        timers.cross-project-scan = {
          Unit.Description = description;
          Timer = {
            OnCalendar = [ "07:30" ];
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
