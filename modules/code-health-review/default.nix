{
  config,
  lib,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.code-health-review;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Hourly code-health tick: start one structure review lead per enrolled repo whose review signal fires";
in
{
  options.myConfig.modules.code-health-review.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.code-health-review = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "10min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin"
              "CODE_HEALTH_ACCOUNT=a"
            ];
            ExecStart = jobRun "code-health-review" "${homeDir}/.local/share/north/bin/code-health-tick";
          };
        };
        timers.code-health-review = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "hourly";
            RandomizedDelaySec = "5min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
