{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-ram;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.nexus-ram.enable =
    lib.mkEnableOption "nexus-ram: every minute append memory, swap, zram, PSI, CPU steal and resident agent CLI usage to ~/.local/state/nexus-ram";
  config = lib.mkIf cfg.enable {
    systemd = {
      services.nexus-ram = {
        description = "Append one nexus-ram row: MemAvailable, swap, zram, memory, CPU and IO PSI, CPU steal and resident agent CLI PSS";
        unitConfig.ConditionFileIsExecutable = "${northBin}/north";
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          Nice = 10;
          TimeoutStartSec = "50s";
          ExecStart = "${northBin}/north nexus-ram record";
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
