{ config, lib, ... }:
let
  cfg = config.myConfig.modules.wm-facts;
in
{
  options.myConfig.modules.wm-facts.enable =
    lib.mkEnableOption "wm-facts-daemon: append niri window facts to the wm-world log";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = {
      systemd.user.services.wm-facts-daemon = {
        Install.WantedBy = [ "niri.service" ];
        Service = {
          ExecStart = "${config.myConfig.modules.users.homeDir}/.local/share/firn/bin/wm-facts-daemon";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Unit = {
          After = [ "graphical-session.target" ];
          Description = "wm-facts-daemon (niri window facts)";
          PartOf = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
      };
    };
  };
}
