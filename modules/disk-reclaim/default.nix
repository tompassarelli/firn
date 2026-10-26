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
    lib.mkEnableOption "disk-reclaim: hourly remove /tmp scratch and Wisp LAN pair copies idle 24 h and held by no process or pool";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.disk-reclaim = {
        description = "Remove /tmp scratch and Wisp LAN pair copies idle 24 h and held by no process or pool";
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
