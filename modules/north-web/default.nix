{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.north-web.enable = lib.mkEnableOption "North web (:8088) — Phoenix cockpit for north agents";
  config = lib.mkIf config.myConfig.modules.north-web.enable {
    systemd.services.north-web = {
      description = "North web (:8088) — Phoenix cockpit over the north coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "north-coord.service" ];
      path = with pkgs; [ bash coreutils git nix direnv ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = homeDir;
        PORT = "8088";
        LANG = "en_US.UTF-8";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = "${codeDir}/north/web";
        ExecStart = "${pkgs.direnv}/bin/direnv exec ${codeDir}/north ${pkgs.bash}/bin/bash -c 'exec mix phx.server'";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
