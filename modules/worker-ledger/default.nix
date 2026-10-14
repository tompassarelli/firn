{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.worker-ledger;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "worker-ledger: every 15 minutes record finished Claude, Codex and Gemini workers as runs in threads, fill landings of runs still waiting to land, and snapshot account usage (agents usage)";
in
{
  options.myConfig.modules.worker-ledger.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.worker-ledger = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "10min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${
                lib.makeBinPath [
                  pkgs.python3
                  pkgs.jq
                  pkgs.git
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.gnugrep
                ]
              }"
            ];
            ExecStart = jobRun "worker-ledger" "${homeDir}/.local/share/north/bin/worker-ledger";
            ExecStartPost = "${homeDir}/.local/share/north/bin/agents usage --refresh";
          };
        };
        timers.worker-ledger = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "5min";
            OnUnitActiveSec = "15min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
