{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.coverage-map-refresh;
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
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "2h";
            Environment = [
              "PATH=${unitPath}"
            ];
            ExecStart = jobRun "coverage-map-refresh" "${northBin}/north test coverage refresh --repo north";
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
