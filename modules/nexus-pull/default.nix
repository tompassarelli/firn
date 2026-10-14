{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-pull;
  username = config.myConfig.modules.users.username;
  description = "nexus-pull: daily rsync of nexus's encrypted *.age backups into ~/backups/nexus, plus a weekly restore test";
  path = "PATH=/run/wrappers/bin:${
    lib.makeBinPath [
      pkgs.openssh
      pkgs.rsync
      pkgs.age
      pkgs.zstd
      pkgs.sqlite
      pkgs.findutils
      pkgs.coreutils
      pkgs.gnused
    ]
  }";
  pull = pkgs.writeShellApplication {
    name = "nexus-pull";
    runtimeInputs = [
      pkgs.openssh
      pkgs.rsync
      pkgs.findutils
      pkgs.coreutils
    ];
    text = builtins.readFile ./nexus-pull.sh;
  };
  restoreTest = pkgs.writeShellApplication {
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
  };
in
{
  options.myConfig.modules.nexus-pull.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pull
      restoreTest
    ];
    home-manager.users.${username} = _: {
      systemd.user = {
        services = {
          nexus-pull = {
            Unit = {
              Description = "Pull nexus's encrypted backups";
              OnFailure = [ "update-notify@%N.service" ];
            };
            Service = {
              Type = "oneshot";
              Environment = [ path ];
              ExecStart = jobRun "nexus-pull" "${pull}/bin/nexus-pull";
            };
          };
          nexus-restore-test = {
            Unit = {
              Description = "Decrypt the newest nexus backups in tmpfs and check their integrity";
              OnFailure = [ "update-notify@%N.service" ];
            };
            Service = {
              Type = "oneshot";
              Environment = [ path ];
              ExecStart = jobRun "nexus-restore-test" "${restoreTest}/bin/nexus-restore-test";
            };
          };
        };
        timers = {
          nexus-pull = {
            Unit.Description = "Pull nexus's encrypted backups daily and after boot";
            Timer = {
              OnCalendar = "*-*-* 05:30:00";
              Persistent = true;
              OnBootSec = "10min";
            };
            Install.WantedBy = [ "timers.target" ];
          };
          nexus-restore-test = {
            Unit.Description = "Weekly nexus backup restore test";
            Timer = {
              OnCalendar = "Sun *-*-* 06:00:00";
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
  };
}
