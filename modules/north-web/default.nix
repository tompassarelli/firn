{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  northWebPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".north-web;
in
{
  options.myConfig.modules.north-web.enable = lib.mkEnableOption "North web (:8088) — bjs/Bun cockpit for north agents";
  config = lib.mkIf config.myConfig.modules.north-web.enable {
    systemd.services.north-web = {
      description = "North web (:8088) — bjs/Bun cockpit over the north coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "north-coord.service" ];
      startLimitIntervalSec = 0;
      restartIfChanged = true;
      environment = {
        HOME = homeDir;
        FRAM_LOG = "${homeDir}/.local/state/north/coordination.log";
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
        NORTH_PORT = "7977";
        NORTH_WEB_BIND = "127.0.0.1";
        PORT = "8088";
        LANG = "en_US.UTF-8";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${northWebPkg}/libexec/north-web";
        ExecStart = "${northWebPkg}/bin/north-web";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
