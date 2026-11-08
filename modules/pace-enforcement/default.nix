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
  cfg = config.myConfig.modules.pace-enforcement;
  username = config.myConfig.modules.users.username;
  description = "pace-enforcement: sample each provider account's usage windows every minute for north's spend rule";
  path = "PATH=${unitPath}:${
    lib.makeBinPath [
      pkgs.python3
      pkgs.openssh
      pkgs.coreutils
      pkgs.systemd
    ]
  }";
in
{
  options.myConfig.modules.pace-enforcement.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.pace-enforcement = {
          Unit = {
            Description = description;
            X-SwitchMethod = "keep-old";
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            TimeoutStartSec = "110s";
            Environment = [ path ];
            ExecStart = jobRun "pace-enforcement" "${northBin}/pace-control";
          };
        };
        timers.pace-enforcement = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* *:*:00";
            AccuracySec = "1s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
