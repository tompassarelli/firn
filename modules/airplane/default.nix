{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.airplane;
  username = config.myConfig.modules.users.username;
  description = "airplane: radios change only through the `airplane` command; keys never toggle rfkill";
in
{
  options.myConfig.modules.airplane.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    systemd = {
      tmpfiles.rules = [ "d /var/lib/airplane 0755 ${username} users -" ];
      services.rfkill-guard = {
        inherit description;
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-rfkill.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 -I ${./rfkill-guard.py} /var/lib/airplane/state";
          Restart = "always";
          RestartSec = "1s";
        };
      };
    };
  };
}
