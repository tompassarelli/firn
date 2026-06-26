{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.lodestar-coord.enable = lib.mkEnableOption "Personal Lodestar coordinator daemon (:7977) — sole-writer claim-graph service for Tom's canonical log";
  config = lib.mkIf config.myConfig.modules.lodestar-coord.enable {
    systemd.services.lodestar-coord = {
      description = "Lodestar coordinator — personal claim-graph daemon (:7977)";
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
        ExecStart = "${codeDir}/fram/bin/fram-daemon 7977 ${homeDir}/.local/state/lodestar/claims.log";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
