{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.usage-sample;
  username = config.myConfig.modules.users.username;
  description = "usage-sample: record each Claude account's 5h and 7d usage into the usage table every minute";
in
{
  options.myConfig.modules.usage-sample.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.usage-sample = {
          Unit = {
            Description = description;
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "control.slice";
            Type = "oneshot";
            TimeoutStartSec = "55s";
            Environment = [
              "PATH=${unitPath}:${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.openssh
                ]
              }"
            ];
            ExecStart = jobRun "usage-sample" "${northBin}/north fleet usage sample";
          };
        };
        timers.usage-sample = {
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
