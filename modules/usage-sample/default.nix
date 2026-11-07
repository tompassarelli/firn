{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.usage-sample;
  homeDir = config.myConfig.modules.users.homeDir;
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
            Type = "oneshot";
            TimeoutStartSec = "55s";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.nix-profile/bin:${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.openssh
                ]
              }"
            ];
            ExecStart = jobRun "usage-sample" "${northBin}/north usage sample";
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
