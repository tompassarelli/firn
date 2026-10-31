{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.fleet-tick;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "fleet-tick: flush this host's north fleet spool, publish its sessions and deliver the rows addressed to them";
  path = "PATH=${northBin}:/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.nix-profile/bin:${homeDir}/.local/share/firn/bin:${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.openssh
    ]
  }";
in
{
  options.myConfig.modules.fleet-tick = {
    enable = lib.mkEnableOption description;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.fleet-tick = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            TimeoutStartSec = "25s";
            Environment = [ path ];
            ExecStart = jobRun "fleet-tick" "${northBin}/north fleet tick";
          };
        };
        timers.fleet-tick = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30s";
            AccuracySec = "1s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
