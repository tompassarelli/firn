{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.job-watch;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.job-watch.enable =
    lib.mkEnableOption "job-watch: every 15 min, push an alert when a registry job with a deadline is overdue";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.job-watch = {
        description = "Alert once when a registered scheduled job is overdue, and when it recovers";
        after = [ "nexus-peers.service" ];
        path = [
          pkgs.python3
          pkgs.coreutils
          "/run/current-system/sw"
        ];
        environment.NORTH_BIN = "${northBin}/north";
        serviceConfig = {
          Type = "oneshot";
          User = username;
          StateDirectory = "job-watch";
          TimeoutStartSec = "5min";
          ExecStart = jobRun "job-watch" "${northBin}/job-watch run";
        };
      };
      timers.job-watch = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:7/15";
          Persistent = true;
        };
      };
    };
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            action.lookup('unit') == 'job-watch.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
  };
}
