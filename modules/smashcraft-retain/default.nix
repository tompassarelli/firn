{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.smashcraft-retain;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "smashcraft-retain: hourly archive gex45 Smashcraft evidence and capture batches past their age to ~/archive/smashcraft-gex45, sha256 verified, then delete the gex45 copy";
in
{
  options.myConfig.modules.smashcraft-retain.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.smashcraft-retain = {
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
            ExecStart = jobRun "smashcraft-retain" "${northBin}/north retain";
          };
        };
        timers.smashcraft-retain = {
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
