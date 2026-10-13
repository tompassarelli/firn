{ config, lib, pkgs, jobRun, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "pace-enforcement: measure provider burn and control worker admission every minute";
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${homeDir}/.nix-profile/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [ pkgs.python3 pkgs.openssh pkgs.coreutils pkgs.systemd ]}";
in {
  options.myConfig.modules.pace-enforcement.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.pace-enforcement.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.pace-enforcement = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          TimeoutStartSec = "110s";
          Environment = [ path ];
          ExecStart = jobRun "pace-enforcement" "${homeDir}/.local/share/north/bin/pace-control";
        };
      };
      systemd.user.timers.pace-enforcement = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = "*-*-* *:*:00";
          AccuracySec = "1s";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}
