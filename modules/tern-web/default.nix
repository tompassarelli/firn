{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.tern-web.enable = lib.mkEnableOption "Tern web (:8088) — Phoenix cockpit for tern agents";
  config = lib.mkIf config.myConfig.modules.tern-web.enable {
    systemd.services.tern-web = {
      description = "Tern web (:8088) — Phoenix cockpit over the tern coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "tern-coord.service" ];
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
        WorkingDirectory = "${codeDir}/tern/web";
        ExecStart = "${pkgs.direnv}/bin/direnv exec ${codeDir}/tern ${pkgs.bash}/bin/bash -c 'exec mix phx.server'";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
