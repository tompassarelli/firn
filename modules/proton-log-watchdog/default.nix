{ config, lib, pkgs, jobRun, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.proton-log-watchdog.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.proton-log-watchdog.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.proton-log-watchdog = {
        Unit = {
          Description = description;
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.libnotify ]}"
          ];
          ExecStart = jobRun "proton-log-watchdog" "${homeDir}/.local/bin/proton-log-watchdog";
        };
      };
      systemd.user.timers.proton-log-watchdog = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnStartupSec = "1min";
          OnUnitActiveSec = "10min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "Proton debug-log watchdog: PROTON_LOG on Wisp clones wrote ~280 GB per clone at 100+ MB/s and hung the desktop, so strip it from launch.sh and truncate clone steam-*.log over 1 GiB")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
