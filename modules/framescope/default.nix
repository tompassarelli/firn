{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.framescope.enable = lib.mkEnableOption "Lodestar web bridge (:8088) — live observatory cockpit for lodestar agents";
  config = lib.mkIf config.myConfig.modules.framescope.enable {
    systemd.services.framescope = {
      description = "Lodestar web — observatory bridge (:8088) projecting the agent coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "agent-coord.service" ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/lodestar/observatory";
        ExecStart = "${pkgs.babashka}/bin/bb bridge/bridge.clj 8088";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
