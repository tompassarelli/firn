{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-land-drill;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Nightly north land drill: inject each lander stuck state into a scratch lander and require its remedy to clear it with nobody paged";
in
{
  options.myConfig.modules.north-land-drill.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-land-drill = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "1h";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.git
                  pkgs.systemd
                  pkgs.util-linux
                ]
              }"
            ];
            ExecStart = jobRun "north-land-drill" "${northBin}/north land drill";
          };
        };
        timers.north-land-drill = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 02:45:00";
            RandomizedDelaySec = "15min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
