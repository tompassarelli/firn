{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
in
{
  options.myConfig.modules.north-coord.enable = lib.mkEnableOption "Personal North coordinator daemon (:7977) — sole-writer fact-graph service for Tom's canonical log";
  config = lib.mkIf config.myConfig.modules.north-coord.enable {
    systemd.services.north-coord = {
      description = "North coordinator — personal fact-graph daemon (:7977)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = true;
      environment = {
        HOME = homeDir;
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${framPkg}/libexec/fram";
        ExecStart = "${framPkg}/bin/fram-daemon 7977 ${homeDir}/.local/state/north/coordination.log";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
