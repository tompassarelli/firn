{ config, lib, pkgs, jobRun, ... }:

((username: ((description: ((path: ((pull: ((restoreTest: {
  options.myConfig.modules.nexus-pull.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.nexus-pull.enable {
    environment.systemPackages = [ pull restoreTest ];
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.nexus-pull = {
        Unit = {
          Description = "Pull nexus's encrypted backups";
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [ path ];
          ExecStart = jobRun "nexus-pull" "${pull}/bin/nexus-pull";
        };
      };
      systemd.user.timers.nexus-pull = {
        Unit = {
          Description = "Pull nexus's encrypted backups daily and after boot";
        };
        Timer = {
          OnCalendar = "*-*-* 05:30:00";
          Persistent = true;
          OnBootSec = "10min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.nexus-restore-test = {
        Unit = {
          Description = "Decrypt the newest nexus backups in tmpfs and check their integrity";
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [ path ];
          ExecStart = jobRun "nexus-restore-test" "${restoreTest}/bin/nexus-restore-test";
        };
      };
      systemd.user.timers.nexus-restore-test = {
        Unit = {
          Description = "Weekly nexus backup restore test";
        };
        Timer = {
          OnCalendar = "Sun *-*-* 06:00:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) (pkgs.writeShellApplication {
    name = "nexus-restore-test";
    runtimeInputs = [
      pkgs.openssh
      pkgs.age
      pkgs.zstd
      pkgs.sqlite
      pkgs.findutils
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ./nexus-restore-test.sh;
  }))) (pkgs.writeShellApplication {
    name = "nexus-pull";
    runtimeInputs = [ pkgs.openssh pkgs.rsync pkgs.findutils pkgs.coreutils ];
    text = builtins.readFile ./nexus-pull.sh;
  }))) "PATH=/run/wrappers/bin:${lib.makeBinPath [
    pkgs.openssh
    pkgs.rsync
    pkgs.age
    pkgs.zstd
    pkgs.sqlite
    pkgs.findutils
    pkgs.coreutils
    pkgs.gnused
  ]}")) "nexus-pull: daily rsync of nexus's encrypted *.age backups into ~/backups/nexus, plus a weekly restore test")) config.myConfig.modules.users.username)
