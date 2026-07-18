{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
  beaglePkg = inputs.beagle.packages."${pkgs.stdenv.hostPlatform.system}".default;
  webBjs = "${codeDir}/north/web-bjs";
in
{
  options.myConfig.modules.north-web.enable = lib.mkEnableOption "North web (:8088) — bjs/Bun cockpit for north agents";
  config = lib.mkIf config.myConfig.modules.north-web.enable {
    systemd.services.north-web = {
      description = "North web (:8088) — bjs/Bun cockpit over the north coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "north-coord.service" ];
      path = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.bun beaglePkg ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
        FRAM_LOG = "${homeDir}/.local/state/north/coordination.log";
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
        PORT = "8088";
        STATIC_DIR = "${codeDir}/north/web/priv/static";
        LANG = "en_US.UTF-8";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = webBjs;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'exec beagle build src/*.bjs --out out'";
        ExecStart = "${pkgs.bun}/bin/bun run out/north/boot.js";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
