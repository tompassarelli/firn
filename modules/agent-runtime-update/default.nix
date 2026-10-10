{ config, lib, pkgs, ... }:

((homeDir: ((username: {
  options.myConfig.modules.agent-runtime-update.enable = lib.mkEnableOption "Twice-daily agent runtime updates";
  config = lib.mkIf config.myConfig.modules.agent-runtime-update.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.agent-runtime-update = {
        Unit = {
          Description = "Twice-daily agent runtime updates";
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          TimeoutStartSec = "4h";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/north/bin:${homeDir}/.local/bin:${lib.makeBinPath [
              pkgs.bash
              pkgs.bun
              pkgs.coreutils
              pkgs.curl
              pkgs.git
              pkgs.gh
              pkgs.nix
              pkgs.python3
              pkgs.zstd
              pkgs.gnutar
              pkgs.gzip
              pkgs.util-linux
              pkgs.libnotify
              pkgs.systemd
            ]}"
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/agent-runtime-update";
        };
      };
      systemd.user.timers.agent-runtime-update = {
        Unit = {
          Description = "Twice-daily agent runtime updates";
        };
        Timer = {
          OnCalendar = [ "02:00" "13:00" ];
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
