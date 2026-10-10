{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.worker-ledger.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.worker-ledger.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.worker-ledger = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "10min";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${lib.makeBinPath [
              pkgs.python3
              pkgs.jq
              pkgs.git
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
            ]}"
          ];
          ExecStart = "${homeDir}/.local/bin/worker-ledger";
        };
      };
      systemd.user.timers.worker-ledger = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnBootSec = "5min";
          OnUnitActiveSec = "15min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "worker-ledger: every 15 minutes record finished Claude and Codex workers as runs in threads, and fill landings of runs still waiting to land")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
