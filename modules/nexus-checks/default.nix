{ config, lib, pkgs, jobRun, ... }:

((username: ((stateDir: ((authorizedKeys: ((checks: ((heartbeat: ((timer: {
  options.myConfig.modules.nexus-checks.enable = lib.mkEnableOption "nexus standing checks (logins, failed units, update age, disk, backup, weekly lynis) with ntfy alerts and a GitHub heartbeat";
  config = lib.mkIf config.myConfig.modules.nexus-checks.enable {
    environment.systemPackages = [ checks ];
    systemd.services = {
      "nexus-checks" = {
        description = "Run the nexus standing checks and push alerts on change";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nexus-checks";
          ExecStart = jobRun "nexus-checks" "${checks}/bin/nexus-checks run";
        };
      };
      "nexus-lynis" = {
        description = "Weekly lynis audit; alert when the hardening index drops or a new warning appears";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nexus-checks";
          Nice = 10;
          ExecStart = jobRun "nexus-lynis" "${checks}/bin/nexus-checks --lynis";
        };
      };
      "nexus-heartbeat" = {
        description = "Publish the nexus check status to the NEXUS_HEARTBEAT variable on GitHub";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment = {
          GH_CONFIG_DIR = "${stateDir}/gh";
        };
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nexus-checks";
          ExecStart = jobRun "nexus-heartbeat" "${heartbeat}/bin/nexus-heartbeat";
        };
      };
    };
    systemd.timers = {
      "nexus-checks" = timer "*:0/15";
      "nexus-lynis" = timer "Sat 21:30";
      "nexus-heartbeat" = timer "*:0/30";
    };
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            ['nexus-checks.service', 'nexus-lynis.service', 'nexus-heartbeat.service'].indexOf(action.lookup('unit')) >= 0 &&
            action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
  };
}) (calendar: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = calendar;
      Persistent = true;
      RandomizedDelaySec = "2m";
    };
  }))) (pkgs.writeShellApplication {
    name = "nexus-heartbeat";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep "/run/current-system/sw" ];
    runtimeEnv = {
      CHECKS_STATE = stateDir;
      HEARTBEAT_REPO = "tompassarelli/firn";
    };
    text = builtins.readFile ./nexus-heartbeat.sh;
  }))) (pkgs.writeShellApplication {
    name = "nexus-checks";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.systemd
      pkgs.openssh
      pkgs.lynis
      "/run/current-system/sw"
    ];
    runtimeEnv = {
      WG_PEERS = "10.77.0.2=laptop 10.77.0.3=phone";
      AUTHORIZED_KEYS = authorizedKeys;
      USER_NAME = username;
      BACKUP_MARKER = "/var/lib/nexus-backup/last-ok";
    };
    text = builtins.readFile ./nexus-checks.sh;
  }))) (pkgs.writeText "nexus-authorized-keys" (lib.concatStringsSep "\n" config.myConfig.modules.users.authorizedKeys)))) "/var/lib/nexus-checks")) config.myConfig.modules.users.username)
