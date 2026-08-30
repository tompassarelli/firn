{ config, lib, pkgs, ... }:

((username: ((homeDir: ((selectionEnv: ((coordinator: ((launch: {
  options.myConfig.modules.north-coordinator.enable = lib.mkEnableOption "North's embedded Beagle Store coordinator on :7977";
  config = lib.mkIf config.myConfig.modules.north-coordinator.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-coordinator = {
        Unit = {
          Description = "North coordinator with embedded Beagle Store on :7977";
          ConditionPathExists = [ selectionEnv coordinator ];
          Conflicts = [ "north-store.service" ];
          After = [ "network.target" "north-store.service" ];
        };
        Service = {
          Type = "simple";
          Environment = [
            "NORTH_COORDINATOR_SELECTION=${selectionEnv}"
            "NORTH_COORDINATOR_EXECUTABLE=${coordinator}"
          ];
          ExecStart = "${launch}/bin/north-coordinator-launch";
          Restart = "on-failure";
          RestartSec = "2s";
          TimeoutStartSec = "120";
          RuntimeMaxSec = "86400";
          CPUQuota = "100%";
          MemoryHigh = "2G";
          MemoryMax = "3G";
          TasksMax = "128";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    });
  };
}) (pkgs.writeShellApplication {
    name = "north-coordinator-launch";
    runtimeInputs = with pkgs; [ coreutils gnused ];
    text = builtins.readFile ./north-coordinator-launch;
  }))) "${homeDir}/code/north/main/bin/north-coordinator")) "${homeDir}/.local/state/north/beagle-store.env")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
