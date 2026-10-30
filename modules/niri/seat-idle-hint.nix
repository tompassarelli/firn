{
  config,
  lib,
  ...
}:

let
  cfg = config.myConfig.modules.niri;
  username = config.myConfig.modules.users.username;
  north = "${config.myConfig.modules.users.homeDir}/.local/share/north/bin/north";
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.seat-idle-hint = {
        Unit = {
          Description = "logind IdleHint from Wayland input idle, which ignores idle inhibitors";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${north} capacity seat-idle-hint --seconds 300";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "niri.service" ];
      };
    };
  };
}
