{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.fleet-relay;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "fleet-relay: deliver the north fleet messages other hosts posted for sessions on this one";
  path = "PATH=${northBin}:/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.nix-profile/bin:${homeDir}/.local/share/firn/bin:${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.openssh
    ]
  }";
in
{
  options.myConfig.modules.fleet-relay = {
    enable = lib.mkEnableOption description;
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "ssh destinations whose north fleet outbox this host drains";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.fleet-relay = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            TimeoutStartSec = "50s";
            Environment = [ path ];
            ExecStart = jobRun "fleet-relay" "${northBin}/north fleet relay ${lib.escapeShellArgs cfg.hosts}";
          };
        };
        timers.fleet-relay = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "minutely";
            AccuracySec = "5s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
