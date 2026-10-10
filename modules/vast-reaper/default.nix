{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.vast-reaper.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.vast-reaper.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.vast-reaper = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/north/bin:${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.bun pkgs.coreutils pkgs.sops pkgs.gh pkgs.libnotify ]}"
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/vast-reaper";
        };
      };
      systemd.user.timers.vast-reaper = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "vast.ai reaper: every 5 minutes destroy vast-job instances past their deadline or without a live supervisor, and tear down the runner VM at the credit floor")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
