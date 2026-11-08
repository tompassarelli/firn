{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.state-backup-push;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  description = "state-backup-push: daily zstd+age encrypted archive of agent state and transcripts, sent to the append-only backup-vault on another host";
  keyPath = config.sops.secrets.state-backup-push-key.path;
  common = ''
    recipients=(${lib.escapeShellArgs cfg.recipients})
    paths=(${lib.escapeShellArgs cfg.paths})
    excludes=(${lib.escapeShellArgs cfg.excludes})
    ledger_dbs=(${lib.escapeShellArgs cfg.ledgerDbs})
    out=${homeDir}/backups/state-push
    keep_days=8
  '';
  backup = pkgs.writeShellApplication {
    name = "state-backup-push-archive";
    runtimeInputs = [
      pkgs.age
      pkgs.zstd
      pkgs.sqlite
      pkgs.gnutar
      pkgs.findutils
      pkgs.coreutils
    ];
    text = common + builtins.readFile ../nexus-backup/state-backup.sh;
  };
  push = pkgs.writeShellApplication {
    name = "state-backup-push-send";
    runtimeInputs = [
      pkgs.openssh
      pkgs.findutils
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      out=${homeDir}/backups/state-push
      keep_days=8
      key=${keyPath}
      vault_host=${cfg.vaultHost}
      ${builtins.readFile ./push.sh}'';
  };
  run = pkgs.writeShellScript "state-backup-push" ''
    ${backup}/bin/state-backup-push-archive && ${push}/bin/state-backup-push-send
  '';
in
{
  options.myConfig.modules.state-backup-push = {
    enable = lib.mkEnableOption description;
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file holding state-backup-push-key, the private ssh key that may only put new archives into the vault";
    };
    recipients = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      description = "age public recipients; the laptop keeps no identity that opens the archives it sends";
    };
    vaultHost = lib.mkOption {
      type = lib.types.str;
      default = "10.77.0.1";
      description = "address of the backup-vault host";
    };
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${homeDir}/.local/state/agents"
        "${homeDir}/.claude/projects"
        "${homeDir}/.codex/sessions"
        "${homeDir}/code/north-data"
      ];
      description = "State and transcript paths archived daily (incremental) and weekly (full)";
    };
    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        map (p: "${homeDir}/.local/state/agents/${p}") [
          "lane-gc"
          "lane-archive"
          "bc-lane-archive"
          "handoffs"
          "scratch"
          "muove-bench"
          "private/hurtbox-fit"
        ]
        ++ map (p: "${homeDir}/code/north-data/${p}") [
          "accounts-retired"
          "codex-pooled"
          "archives"
          "runtimes"
          "bench"
          "fram-cutovers"
          "land-queue"
          "fleet/.archive"
          "fleet/.hosts"
        ];
      description = "Bulk that is rebuilt or scratch: retired lanes, handoffs, pooled and retired accounts, archives";
    };
    ledgerDbs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${homeDir}/code/north-data/ledger.db" ];
      description = "SQLite ledgers dumped consistently through .backup";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.state-backup-push-key = {
      owner = username;
      inherit (cfg) sopsFile;
    };
    home-manager.users.${username} = _: {
      systemd.user = {
        services.state-backup-push = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%N.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 15;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "3h";
            Environment = [ "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.coreutils ]}" ];
            ExecStart = jobRun "state-backup-push" "${run}";
          };
        };
        timers.state-backup-push = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 04:30:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
