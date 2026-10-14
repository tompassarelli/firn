{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.outside-watch;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "outside-watch: every 10 minutes minimize and block spam on Tom's GitHub repos, report real people to the proxy inbox and mark our own notifications read";
in
{
  options.myConfig.modules.outside-watch.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.outside-watch = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/north/bin:${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.gh
                  pkgs.python3
                ]
              }"
            ];
            ExecStart = jobRun "outside-watch" "${homeDir}/.local/share/north/bin/outside-watch run";
          };
        };
        timers.outside-watch = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*:0/10";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
