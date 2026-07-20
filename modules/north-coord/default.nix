{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
  framRev = inputs.fram.rev;
  runtimeState = "${homeDir}/.local/state/north/fram-runtime";
  northCoordRuntime = pkgs.writeShellApplication {
    name = "north-coord-runtime";
    runtimeInputs = with pkgs; [ bash coreutils git ];
    text = ''
      export NORTH_COORD_RUNTIME_STATE=${runtimeState}
      export NORTH_COORD_FRAM_PACKAGE=${framPkg}
      export NORTH_COORD_FRAM_PACKAGE_REV=${framRev}
      export NORTH_COORD_FRAM_CHECKOUT=${homeDir}/code/fram
      export NORTH_COORD_FRAM_LOG=${homeDir}/.local/state/north/coordination.log
      ${builtins.readFile ./north-coord-runtime}
    '';
  };
in
{
  options.myConfig.modules.north-coord.enable = lib.mkEnableOption "Personal North coordinator daemon (:7977) — sole-writer fact-graph service for Tom's canonical log";
  config = lib.mkIf config.myConfig.modules.north-coord.enable {
    environment.systemPackages = [ northCoordRuntime ];
    systemd.services.north-coord = {
      description = "North coordinator — personal fact-graph daemon (:7977)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = true;
      environment = {
        HOME = homeDir;
        FRAM_REQUIRE_LOG_FENCE = "1";
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = homeDir;
        ExecStart = "${northCoordRuntime}/bin/north-coord-runtime start";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
