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
  cfg = config.myConfig.modules.incident-retro;
  username = config.myConfig.modules.users.username;
  description = "Weekly sampled retro: mine the last 7 days of transcripts, sample every fifth candidate and launch one Haiku session that files recurring failure modes with no enforcer";
in
{
  options.myConfig.modules.incident-retro.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.incident-retro = {
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
            ExecStart = jobRun "incident-retro" "${northBin}/north incident-retro";
          };
        };
        timers.incident-retro = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "Thu *-*-* 09:30:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
