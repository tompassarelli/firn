{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.watch-review;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Daily watch-review: launch one fleet session per due followed source (30 days since its last review with new commits, or 10 new commits) and tell the proxy when a launch fails or is held";
in
{
  options.myConfig.modules.watch-review.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.watch-review = {
          Unit = {
            Description = description;
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "30min";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${lib.makeBinPath [ pkgs.git ]}"
            ];
            ExecStart = jobRun "watch-review" "${northBin}/north watch-review";
          };
        };
        timers.watch-review = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 09:00:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
