{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  selectionEnv = "${homeDir}/.local/state/north/framrpc.env";
  unitName = "north-fram.service";
  launch = pkgs.writeShellApplication {
    name = "north-fram-launch";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ./north-fram-launch;
  };
  publishRuntime = pkgs.writeShellApplication {
    name = "north-fram-publish-runtime";
    runtimeInputs = with pkgs; [ coreutils gnused ];
    text = builtins.readFile ./north-fram-publish-runtime;
  };
in
{
  options.myConfig.modules.north-fram.enable = lib.mkEnableOption "North coordination engine (:7977) — sealed Fram release as one user service";
  config = lib.mkIf config.myConfig.modules.north-fram.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-fram = {
        Unit = {
          Description = "North coordination engine — sealed Fram release on :7977";
          ConditionPathExists = selectionEnv;
          After = [ "network.target" ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          Environment = [
            "NORTH_FRAM_SELECTION=${selectionEnv}"
            "NORTH_COORD_SYSTEMD_UNIT=${unitName}"
          ];
          ExecStart = "${launch}/bin/north-fram-launch";
          ExecStartPost = "-${publishRuntime}/bin/north-fram-publish-runtime $MAINPID";
          ExecStopPost = "-${pkgs.coreutils}/bin/rm -f %S/north/framrpc-runtime/north-fram.runtime";
          Restart = "on-failure";
          RestartSec = "2s";
          TimeoutStartSec = "120";
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
}
