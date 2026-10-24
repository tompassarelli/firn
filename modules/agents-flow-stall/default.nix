{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.agents-flow-stall;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
    lib.makeBinPath [
      pkgs.bun
      pkgs.gh
      pkgs.git
      pkgs.python3
      pkgs.tmux
      pkgs.jq
      pkgs.sqlite
      pkgs.ripgrep
      pkgs.gitleaks
      pkgs.iproute2
      pkgs.coreutils
    ]
  }";
in
{
  options.myConfig.modules.agents-flow-stall.enable =
    lib.mkEnableOption "agents-flow-stall: every five minutes, tell the active Fleet parent and Plato when repository landings stall; enable it on exactly one host, one with gh signed in";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.agents-flow-stall = {
          Unit.Description = "Report stalled repository landings";
          Service = {
            Type = "oneshot";
            Environment = [ path ];
            ExecStart = "${northBin}/agents flow --stall-alert";
          };
        };
        timers.agents-flow-stall = {
          Unit.Description = "Check repository landing progress every five minutes";
          Timer = {
            OnCalendar = "*-*-* *:00/5:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
