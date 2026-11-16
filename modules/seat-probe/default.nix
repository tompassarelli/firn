{
  config,
  lib,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.seat-probe;
  username = config.myConfig.modules.users.username;
  description = "seat-probe: time a synced write of the owner's filesystem every 2 s and stop the fleet's laptop units when one stays out past the trip time (north#1553)";
in
{
  options.myConfig.modules.seat-probe.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.seat-probe = {
        Unit = {
          Description = description;
        };
        Service = {
          # The owner's own slice: agent.slice's and control.slice's caps and load must not reach the probe that judges them.
          Slice = "session.slice";
          ExecStart = "${northBin}/north capacity seat-probe";
          Restart = "always";
          RestartSec = 2;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
