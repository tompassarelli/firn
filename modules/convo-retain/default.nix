{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.convo-retain;
  username = config.myConfig.modules.users.username;
  description = "Daily transcript lifecycle: zstd-compress Claude transcripts idle 30 days and append the messages Tom typed to the Tom corpus";
in
{
  options.myConfig.modules.convo-retain.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.convo-retain = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 19;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "2h";
            Environment = [
              "PATH=${unitPath}"
            ];
            ExecStart = [
              (jobRun "convo-compress" "${northBin}/north convo compress -q")
              (jobRun "convo-corpus" "${northBin}/north convo corpus -q")
            ];
          };
        };
        timers.convo-retain = {
          Unit.Description = description;
          Timer = {
            OnCalendar = [ "*-*-* 04:30" ];
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
