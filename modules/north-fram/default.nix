{ config, lib, pkgs, ... }:

((username: ((homeDir: ((selectionEnv: ((unitName: ((launch: ((publishRuntime: {
  options.myConfig.modules.north-fram.enable = lib.mkEnableOption "North coordination store (:7977) — sealed Beagle Store release as one user service";
  config = lib.mkIf config.myConfig.modules.north-fram.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-fram = {
        Unit = {
          Description = "North coordination store — sealed Beagle Store release on :7977";
          ConditionPathExists = selectionEnv;
          After = [ "network.target" ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          Environment = [
            "NORTH_STORE_SELECTION=${selectionEnv}"
            "NORTH_COORD_SYSTEMD_UNIT=${unitName}"
          ];
          ExecStart = "${launch}/bin/north-fram-launch";
          ExecStartPost = "${publishRuntime}/bin/north-fram-publish-runtime $MAINPID";
          ExecStopPost = "-${pkgs.coreutils}/bin/rm -f %S/north/store-runtime/north-store.runtime";
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
    name = "north-fram-publish-runtime";
    runtimeInputs = with pkgs; [ coreutils gnused ];
    text = builtins.readFile ./north-fram-publish-runtime;
  }))) (pkgs.writeShellApplication {
    name = "north-fram-launch";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ./north-fram-launch;
  }))) "north-fram.service")) "${homeDir}/.local/state/north/beagle-store.env")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
