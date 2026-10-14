{ config, lib, ... }:
let
  cfg = config.myConfig.modules.activity;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      systemd.user.services.activity-daemon = {
        Install.WantedBy = [ "niri.service" ];
        Service = {
          Environment = "Malloc=1";
          ExecStart = "${config.myConfig.modules.users.homeDir}/.local/share/firn/bin/activity daemon";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Unit = {
          After = [ "graphical-session.target" ];
          Description = "activity daemon (niri activity layer)";
          PartOf = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
      };
      xdg.configFile."activity/activities.json".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/${config.myConfig.modules.activity.activitiesFile}";
    };
  };
  options.myConfig.modules.activity = {
    activitiesFile = lib.mkOption {
      type = lib.types.str;
      default = "code/nixos-config/main/dotfiles/activity/activities.json";
      description = "activities.json linked at ~/.config/activity/activities.json, relative to the home directory";
    };
    enable = lib.mkEnableOption "activity — activities own workspaces: two-level layer over niri (daemon + CLI)";
  };
}
