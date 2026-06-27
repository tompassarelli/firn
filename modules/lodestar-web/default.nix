{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.lodestar-web.enable = lib.mkEnableOption "Lodestar web bridge (:8088) — live web cockpit for lodestar agents";
  config = lib.mkIf config.myConfig.modules.lodestar-web.enable {
    systemd.services.lodestar-web = {
      description = "Lodestar web bridge (:8088) — projects the agent coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "agent-coord.service" ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/lodestar/web";
        ExecStart = "${pkgs.babashka}/bin/bb bridge/bridge.clj 8088";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
