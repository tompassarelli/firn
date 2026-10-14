{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.modules.agents-supervise;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "agents supervise: deliver agent events to their target sessions every 30 s and raise stalled ones";
in {
  options.myConfig.modules.agents-supervise.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.agents-supervise = {
        Unit = {
          Description = description;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          Environment = [
            "PATH=/run/wrappers/bin:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.jq
              pkgs.python3
              pkgs.git
              pkgs.tmux
              pkgs.websocat
              pkgs.procps
              pkgs.util-linux
            ]}:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin"
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/agents supervise";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    });
  };
}
