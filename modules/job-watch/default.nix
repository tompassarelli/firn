{ config, lib, pkgs, jobRun, ... }:

((username: ((homeDir: {
  options.myConfig.modules.job-watch.enable = lib.mkEnableOption "job-watch: every 15 min, push an alert when a registry job with a deadline is overdue";
  config = lib.mkIf config.myConfig.modules.job-watch.enable {
    systemd.services.job-watch = {
      description = "Alert once when a registered scheduled job is overdue, and when it recovers";
      after = [ "nexus-peers.service" ];
      path = [ pkgs.python3 pkgs.coreutils "/run/current-system/sw" ];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        StateDirectory = "job-watch";
        TimeoutStartSec = "5min";
        ExecStart = jobRun "job-watch" "${homeDir}/.local/share/north/bin/job-watch run";
      };
    };
    systemd.timers.job-watch = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:7/15";
        Persistent = true;
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
}) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
