{
  config,
  lib,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.coverage-map-refresh;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Nightly north coverage map: record which functions each Rust test executes on a check host, for the pre-push test selection";
in
{
  options.myConfig.modules.coverage-map-refresh.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.coverage-map-refresh = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "2h";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin"
            ];
            ExecStart = jobRun "coverage-map-refresh" "${northBin}/north coverage refresh --repo north";
          };
        };
        timers.coverage-map-refresh = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 03:30:00";
            RandomizedDelaySec = "20min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
