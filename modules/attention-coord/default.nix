{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.attention-coord.enable = lib.mkEnableOption "Attention coordinator daemon (:7980) — live file-attention tracking for lodestar web dark-room";
  config = lib.mkIf config.myConfig.modules.attention-coord.enable {
    systemd.services.attention-coord = {
      description = "Attention coordinator — ephemeral claim-graph daemon (:7980) for live agent file-attention tracking";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "agent-coord.service" ];
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/fram";
        ExecStart = "${pkgs.clojure}/bin/clojure -M cnf_coord_daemon.clj serve 7980 ${codeDir}/fleet-data/attention-claims.log";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
