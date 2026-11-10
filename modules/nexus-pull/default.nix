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
  homeDir = config.myConfig.modules.users.homeDir;
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
  restoreCheck = pkgs.writeShellApplication {
    name = "nexus-restore-check";
    runtimeInputs = [
      pkgs.age
      pkgs.zstd
      pkgs.sqlite
      pkgs.findutils
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ./nexus-restore-check.sh;
  };
  restoreTest = pkgs.writeShellApplication {
    name = "nexus-restore-test";
    runtimeInputs = [
      pkgs.openssh
      pkgs.systemd
      pkgs.coreutils
    ];
    text = builtins.readFile ./nexus-restore-test.sh;
  };
in
{
  options.myConfig.modules.nexus-pull.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            action.lookup('unit') == 'nexus-restore-check.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });
    '';
    systemd.services.nexus-restore-check = {
      description = "Decrypt the newest pulled nexus backups and check their integrity";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${restoreCheck}/bin/nexus-restore-check ${homeDir}/backups/nexus";
        LoadCredential = "age-key:/var/lib/sops-nix/key.txt";
        NoNewPrivileges = true;
        PrivateNetwork = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        CapabilityBoundingSet = "CAP_DAC_READ_SEARCH";
        RestrictAddressFamilies = "AF_UNIX";
        SystemCallFilter = "@system-service";
      };
    };
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
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Slice = "control.slice";
              Type = "oneshot";
              Environment = [ path ];
              ExecStart = jobRun "nexus-pull" "${pull}/bin/nexus-pull";
            };
          };
          nexus-restore-test = {
            Unit = {
              Description = "Decrypt the newest nexus backups in tmpfs and check their integrity";
              OnFailure = [ "update-notify@%N.service" ];
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Slice = "agent.slice";
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
