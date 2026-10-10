{ config, lib, pkgs, ... }:

((cfg: ((username: ((homeDir: ((stateBackup: {
  options.myConfig.modules.nexus-backup.enable = lib.mkEnableOption "nexus state-backup: nightly zstd+age encrypted ledger dumps and state archives in /var/lib/nexus-backup";
  options.myConfig.modules.nexus-backup.recipients = lib.mkOption {
    type = lib.types.nonEmptyListOf lib.types.str;
    description = "age public recipients; nexus holds none of the matching identities";
  };
  options.myConfig.modules.nexus-backup.paths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "${homeDir}/.local/state/agents"
      "${homeDir}/.claude/projects"
      "${homeDir}/.codex/sessions"
      "${homeDir}/.local/state/north"
    ];
    description = "State paths archived daily (incremental) and weekly (full); missing paths are skipped";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ stateBackup ];
    systemd.services.state-backup = {
      description = "Encrypted nexus state backup (ledger dumps and state archives)";
      serviceConfig = {
        Type = "oneshot";
        User = username;
        StateDirectory = "nexus-backup";
        StateDirectoryMode = "0700";
        Nice = 10;
        IOSchedulingClass = "idle";
        ExecStart = "${stateBackup}/bin/state-backup";
      };
    };
    systemd.timers.state-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
    };
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            action.lookup('unit') == 'state-backup.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
  };
}) (pkgs.writeShellApplication {
    name = "state-backup";
    runtimeInputs = [ pkgs.age pkgs.zstd pkgs.sqlite pkgs.gnutar pkgs.findutils pkgs.coreutils ];
    text = "recipients=(${lib.escapeShellArgs cfg.recipients})\npaths=(${lib.escapeShellArgs cfg.paths})\n${builtins.readFile ./state-backup.sh}";
  }))) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)) config.myConfig.modules.nexus-backup)
