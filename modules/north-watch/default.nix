{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-watch;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-watch: every 30 s raise landing hiccups to the proxy and the lane's lead";
in
{
  options.myConfig.modules.north-watch.enable = lib.mkEnableOption description // {
    default = config.myConfig.modules.agent-runtime-update.enable;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-watch = {
          Unit.Description = description;
          Service = {
            Type = "oneshot";
            Nice = 5;
            TimeoutStartSec = "5min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gh
                  pkgs.git
                  pkgs.libnotify
                  pkgs.openssh
                ]
              }"
            ];
            ExecStart = "${northBin}/north watch --once";
          };
        };
        timers.north-watch = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "1min";
            OnUnitInactiveSec = "30s";
            AccuracySec = "5s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
