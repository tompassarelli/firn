{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.framescope.enable = lib.mkEnableOption "Framescope observatory bridge (:8088) — live cockpit for the AI agent fleet";
  config = lib.mkIf config.myConfig.modules.framescope.enable {
    systemd.services.framescope = {
      description = "Framescope — observatory bridge (:8088) projecting the fleet coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "fleet-coord.service" ];
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
