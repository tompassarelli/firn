{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.checkout-sync;
  username = config.myConfig.modules.users.username;
  description = "checkout-sync: every 15 min fast-forward each clean ~/code/<project>/main to origin/main on hosts where nothing lands locally";
in
{
  options.myConfig.modules.checkout-sync.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.checkout-sync = {
          Unit.Description = description;
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "10min";
            Environment = [
              "PATH=${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.openssh
                  pkgs.coreutils
                ]
              }:/run/current-system/sw/bin"
            ];
            ExecStart = jobRun "checkout-sync" "${pkgs.bash}/bin/bash ${./checkout-sync.sh}";
          };
        };
        timers.checkout-sync = {
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
