{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.fleet-tick;
  username = config.myConfig.modules.users.username;
  description = "fleet-tick: flush this host's north fleet spool, publish its sessions and deliver the rows addressed to them, and run again the sessions a reboot stranded";
  path = "PATH=${unitPath}:${
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
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            TimeoutStartSec = "50s";
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
