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
    lib.mkEnableOption "disk-reclaim: hourly remove /tmp scratch and Wisp LAN pair copies idle 24 h and held by no process or pool; every 15 minutes keep the shared cargo target under 10 GiB; build with cargo incremental state off";
  config = lib.mkIf cfg.enable {
    systemd = {
      services = {
        disk-reclaim = {
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
        cargo-target-sweep = {
          description = "Keep the shared cargo target under 10 GiB: drop incremental state, idle test binaries and, over the cap, idle libraries";
          unitConfig.ConditionFileIsExecutable = "${northBin}/north";
          serviceConfig = {
            Type = "oneshot";
            User = username;
            Nice = 19;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "10min";
            ExecStart = "${northBin}/north target-sweep";
          };
        };
      };
      timers = {
        disk-reclaim = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            RandomizedDelaySec = "10min";
            Persistent = true;
          };
        };
        cargo-target-sweep = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/15";
            RandomizedDelaySec = "2min";
            Persistent = true;
          };
        };
      };
    };
    home-manager.users.${username}.home.file.".cargo/config.toml" = {
      force = true;
      source = (pkgs.formats.toml { }).generate "cargo-config.toml" {
        build.incremental = false;
      };
    };
  };
}
