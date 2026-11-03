{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.makgora-retain;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "makgora-retain: hourly archive gex45 Mak'gora evidence and capture batches past their age to ~/archive/makgora-gex45, sha256 verified, then delete the gex45 copy";
in
{
  options.myConfig.modules.makgora-retain.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.makgora-retain = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "50min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.openssh
                  pkgs.gnutar
                  pkgs.coreutils
                ]
              }"
            ];
            ExecStart = jobRun "makgora-retain" "${northBin}/north retain";
          };
        };
        timers.makgora-retain = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "15min";
            OnUnitActiveSec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
