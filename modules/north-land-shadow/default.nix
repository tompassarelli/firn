{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-land-shadow;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-land-shadow: every 2 minutes check the next queued lane's candidate on a host with room and store each check line's verdict for the lander";
in
{
  options.myConfig.modules.north-land-shadow.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-land-shadow = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "2h";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/share/firn/bin:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.bun
                  pkgs.coreutils
                  pkgs.git
                  pkgs.gnutar
                  pkgs.nix
                  pkgs.openssh
                  pkgs.rsync
                  pkgs.systemd
                  pkgs.util-linux
                ]
              }"
              "SAFE_PUSH_LAND_RUNNER=gex45"
            ];
            ExecStart = jobRun "north-land-shadow" "${northBin}/north land shadow tick";
          };
        };
        timers.north-land-shadow = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "5min";
            OnUnitActiveSec = "2min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
