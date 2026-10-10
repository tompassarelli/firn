{ config, lib, pkgs, ... }:

((username: ((description: {
  options.myConfig.modules.airplane.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.airplane.enable {
    systemd.tmpfiles.rules = [ "d /var/lib/airplane 0755 ${username} users -" ];
    systemd.services.rfkill-guard = {
      description = description;
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-rfkill.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 -I ${./rfkill-guard.py} /var/lib/airplane/state";
        Restart = "always";
        RestartSec = "1s";
      };
    };
  };
}) "airplane: radios change only through the `airplane` command; keys never toggle rfkill")) config.myConfig.modules.users.username)
