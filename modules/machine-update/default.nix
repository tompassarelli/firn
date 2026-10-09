{ config, lib, pkgs, ... }:

((homeDir: ((username: {
  options.myConfig.modules.machine-update.enable = lib.mkEnableOption "Nightly machine software update";
  config = lib.mkIf config.myConfig.modules.machine-update.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.machine-update = {
        Unit = {
          Description = "Nightly machine software update";
          OnFailure = [ "update-notify@%n.service" ];
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          TimeoutStartSec = "4h";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${lib.makeBinPath [
              pkgs.bash
              pkgs.bun
              pkgs.coreutils
              pkgs.curl
              pkgs.git
              pkgs.gh
              pkgs.nix
              pkgs.python3
              pkgs.zstd
              pkgs.util-linux
              pkgs.libnotify
              pkgs.systemd
            ]}"
          ];
          ExecStart = "${homeDir}/.local/bin/machine-update";
        };
      };
      systemd.user.timers.machine-update = {
        Unit = {
          Description = "Nightly machine software update";
        };
        Timer = {
          OnCalendar = "02:00";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
