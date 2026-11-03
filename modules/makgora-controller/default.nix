{ config, lib, ... }:
let
  cfg = config.myConfig.modules.makgora-controller;
in
{
  options.myConfig.modules.makgora-controller.enable =
    lib.mkEnableOption "padbridge service: Tom's Xbox controller in Warcraft III, with Mak'gora's plug-in";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      systemd.user.services.padbridge = {
        Install.WantedBy = [ "niri.service" ];
        Service = {
          ExecStart = "${hm.config.home.homeDirectory}/.local/share/padbridge/bin/padbridge --service --plugin ${hm.config.home.homeDirectory}/.local/share/makgora-build-inputs/controller/wc3-journal";
          Restart = "always";
          RestartSec = "5";
        };
        Unit = {
          After = [ "graphical-session.target" ];
          ConditionPathExists = "${hm.config.home.homeDirectory}/.local/share/padbridge/bin/padbridge";
          Description = "padbridge service";
          PartOf = [ "graphical-session.target" ];
        };
      };
    };
  };
}
