{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.north-graph-retain;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Daily north graph retain: delete the fact graph's history no reader needs (retired writers, withdrawn pairs below the retention horizon, unreferenced terms) in short transactions, then reclaim the space";
in
{
  options.myConfig.modules.north-graph-retain.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-graph-retain = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "15min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${
                lib.makeBinPath [ pkgs.coreutils ]
              }"
            ];
            ExecStart = jobRun "north-graph-retain" "${northBin}/north graph retain";
          };
        };
        timers.north-graph-retain = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 04:20:00";
            RandomizedDelaySec = "30min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
