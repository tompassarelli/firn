{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.proxy-terminal-watch;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "proxy-terminal-watch: classify every agent terminal and push stopped leads every 5 minutes";
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${homeDir}/.nix-profile/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.procps
      pkgs.ripgrep
      pkgs.jq
      pkgs.gawk
    ]
  }";
in
{
  options.myConfig.modules.proxy-terminal-watch.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.proxy-terminal-watch = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            TimeoutStartSec = "280s";
            Environment = [ path ];
            ExecStart = jobRun "proxy-terminal-watch" "${homeDir}/.local/state/agents/handoffs/proxy-kit/terminal-watch.sh";
          };
        };
        timers.proxy-terminal-watch = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*:0/5";
            AccuracySec = "10s";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
