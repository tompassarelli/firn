{
  config,
  lib,
  pkgs,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.agents-flow-stall;
  username = config.myConfig.modules.users.username;
  path = "PATH=${unitPath}:${
    lib.makeBinPath [
      pkgs.bun
      pkgs.gh
      pkgs.git
      pkgs.python3
      pkgs.tmux
      pkgs.jq
      pkgs.sqlite
      pkgs.ripgrep
      pkgs.betterleaks
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
          Unit = {
            Description = "Report stalled repository landings";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "control.slice";
            Type = "oneshot";
            Environment = [ path ];
            ExecStart = "${northBin}/north ledger flow --stall-alarm";
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
