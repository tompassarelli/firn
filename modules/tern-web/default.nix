{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.tern-web.enable = lib.mkEnableOption "Tern web bridge (:8088) — live web cockpit for tern agents";
  config = lib.mkIf config.myConfig.modules.tern-web.enable {
    systemd.services.tern-web = {
      description = "Tern web bridge (:8088) — projects the agent coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "agent-coord.service" ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/tern/web";
        ExecStart = "${pkgs.babashka}/bin/bb bridge/bridge.clj 8088";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
