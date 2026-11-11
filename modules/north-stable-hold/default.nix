{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.north-stable-hold;
  username = config.myConfig.modules.users.username;
  description = "north-stable-hold: while the stable pin file exists, hold the runtime promotion lock so no landing promotes past the pin";
in
{
  options.myConfig.modules.north-stable-hold.enable = lib.mkEnableOption description // {
    default = config.myConfig.modules.north-land.enable;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.north-stable-hold = {
        Unit = {
          Description = description;
          ConditionPathExists = "%h/.local/state/north/channel/stable";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Slice = "control.slice";
          ExecStart = "${pkgs.util-linux}/bin/flock %h/.local/state/north/runtime-promote.lock ${pkgs.coreutils}/bin/sleep infinity";
          Restart = "on-failure";
          RestartSec = "1s";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
