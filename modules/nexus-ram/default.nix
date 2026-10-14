{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-ram;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
in
{
  options.myConfig.modules.nexus-ram.enable =
    lib.mkEnableOption "nexus-ram: every minute append memory, swap, zram, PSI and resident agent CLI usage to ~/.local/state/nexus-ram";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.nexus-ram = {
        description = "Append one nexus-ram row: MemAvailable, swap, zram, memory PSI and resident agent CLI PSS";
        unitConfig.ConditionPathIsExecutable = "${homeDir}/.local/share/north/bin/nexus-ram";
        path = [
          pkgs.python3
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          Nice = 10;
          TimeoutStartSec = "50s";
          ExecStart = "${homeDir}/.local/share/north/bin/nexus-ram record";
        };
      };
      timers.nexus-ram = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          AccuracySec = "1s";
        };
      };
    };
  };
}
