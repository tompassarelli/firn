{
  config,
  lib,
  ...
}:

let
  cfg = config.myConfig.modules.harness-health;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Deterministic North harness invariant checks";
in
{
  options.myConfig.modules.harness-health.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.harness-health = {
          Unit = {
            Description = description;
            After = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "6min";
            SuccessExitStatus = "1";
            Environment = [
              "PATH=/run/wrappers/bin:${homeDir}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${homeDir}/.local/share/south/bin"
            ];
            ExecStart = "${homeDir}/.local/share/north/bin/north health";
          };
        };
        timers.harness-health = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*:0/2";
            AccuracySec = "15s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
