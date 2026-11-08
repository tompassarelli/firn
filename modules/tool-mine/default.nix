{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.tool-mine;
  username = config.myConfig.modules.users.username;
  description = "Weekly tool mining: file one north#112 box per command sequence 5+ sessions ran in 7 days";
in
{
  options.myConfig.modules.tool-mine.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.tool-mine = {
          Unit = {
            Description = description;
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            Environment = [
              "PATH=${unitPath}:${lib.makeBinPath [ pkgs.git ]}"
            ];
            ExecStart = jobRun "tool-mine" "${northBin}/north tool-mine";
          };
        };
        timers.tool-mine = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "Mon *-*-* 04:17:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
