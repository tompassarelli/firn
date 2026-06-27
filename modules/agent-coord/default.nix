{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.agent-coord.enable = lib.mkEnableOption "Agent coordinator daemon (:7978) — durable claim-graph coordination for lodestar agents";
  config = lib.mkIf config.myConfig.modules.agent-coord.enable {
    systemd.services.agent-coord = {
      description = "Agent coordinator — durable claim-graph daemon (:7978) for lodestar agent coordination";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/fram";
        ExecStart = "${pkgs.clojure}/bin/clojure -M cnf_coord_daemon.clj serve 7978 ${codeDir}/fleet-data/claims.log";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
