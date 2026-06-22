{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.fleet-coord.enable = lib.mkEnableOption "Fleet coordinator daemon (:7978) — durable claim-graph coordination substrate for the AI agent fleet";
  config = lib.mkIf config.myConfig.modules.fleet-coord.enable {
    systemd.services.fleet-coord = {
      description = "Fleet coordinator — durable claim-graph daemon (:7978) for the AI agent fleet";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = "/home/tom";
      };
      serviceConfig = {
        Type = "simple";
        User = "tom";
        WorkingDirectory = "/home/tom/code/fleet-coord";
        ExecStart = "${pkgs.babashka}/bin/bb -cp out cnf_coord_daemon.clj serve 7978 /home/tom/code/fleet-data/claims.log";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
