{ config, lib, pkgs, jobRun, ... }:

((homeDir: ((username: ((description: ((nightly: ((path: {
  options.myConfig.modules.capacity-watchdog.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.capacity-watchdog.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.capacity-watchdog = {
        Unit = {
          Description = description;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          CPUWeight = 200;
          MemoryMax = "512M";
          Environment = [ path ];
          ExecStart = "${homeDir}/.local/share/north/bin/capacity-watchdog sample";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.git-maintenance-nightly = {
        Unit = {
          Description = nightly;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "4h";
          Environment = [ path ];
          ExecStart = jobRun "git-maintenance-nightly" "${homeDir}/.local/share/north/bin/git-maintenance-nightly";
        };
      };
      systemd.user.timers.git-maintenance-nightly = {
        Unit = {
          Description = nightly;
        };
        Timer = {
          OnCalendar = "*-*-* 03:17:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [ pkgs.bun pkgs.git pkgs.coreutils pkgs.libnotify pkgs.systemd ]}")) "git-maintenance-nightly: run git maintenance for ~/code/*/main one repo at a time inside a moderate capacity lease")) "capacity-watchdog: sample load, PSI, cgroup CPU and unleased processes every 30 s; log incidents and stop stray git maintenance")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
