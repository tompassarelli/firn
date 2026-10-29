{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.disk-reclaim;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.disk-reclaim.enable =
    lib.mkEnableOption "disk-reclaim: hourly north reclaim of idle /tmp scratch, Wisp LAN pair copies and cargo targets, and of build and test caches past their size cap";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.disk-reclaim = {
        description = "Remove idle /tmp scratch, Wisp LAN pair copies and cargo targets, and the oldest files of build and test caches past their size cap";
        unitConfig.ConditionFileIsExecutable = "${northBin}/north";
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          Nice = 19;
          IOSchedulingClass = "idle";
          TimeoutStartSec = "20min";
          ExecStart = "${northBin}/north reclaim";
        };
      };
      timers.disk-reclaim = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "10min";
          Persistent = true;
        };
      };
    };
  };
}
