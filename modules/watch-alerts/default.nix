{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.watch-alerts;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Deterministic location safety alerts";
in
{
  options.myConfig.modules.watch-alerts.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.watch-alerts = {
          Unit = {
            Description = description;
            After = [ "network-online.target" ];
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "4min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [ pkgs.python3 ]
              }"
            ];
            ExecStart = "${northBin}/model-watch --alerts-only";
          };
        };
        timers.watch-alerts = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*:0/5";
            AccuracySec = "30s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
