{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.skill-prune;
  username = config.myConfig.modules.users.username;
  description = "Weekly skill and lesson prune";
in
{
  options.myConfig.modules.skill-prune.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.skill-prune = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "100min";
            Environment = [
              "PATH=${unitPath}"
            ];
            ExecStart = jobRun "skill-prune" "${northBin}/north skill-prune";
          };
        };
        timers.skill-prune = {
          Unit.Description = description;
          Timer = {
            OnCalendar = [ "Sun 09:00" ];
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
