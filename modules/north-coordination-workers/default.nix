{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  promotedRuntime = "%h/.local/state/north/runtime/current";
  rebuildWorker = "${promotedRuntime}/cli/nix-rebuild-worker.clj";
  reconciliationWorker = "${promotedRuntime}/cli/reconciliation-worker-host.clj";
  projectionWorker = "${promotedRuntime}/cli/coordination-projection-worker-host.clj";
  maintenanceHost = "${promotedRuntime}/cli/coordination-maintenance-task-host.clj";
  runtimePath = "PATH=${pkgs.systemd}/bin:${pkgs.babashka}/bin:${pkgs.coreutils}/bin:${pkgs.git}/bin";
  rebuildRuntimePath = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.nix-profile/bin";
  firnBin = "FIRN_BIN=${homeDir}/.local/bin/firn";
  northRuntimeExec = pkgs.writeShellApplication {
    name = "north-runtime-exec";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../north/north-runtime-exec;
  };
  restartRuntimeWorkers = pkgs.writeShellApplication {
    name = "north-restart-runtime-workers";
    runtimeInputs = with pkgs; [ systemd ];
    text = "systemctl --user try-restart north-nix-rebuild-worker.service north-concern-reconciliation-worker.service north-attention-reconciliation-worker.service north-coordination-projection-worker.service";
  };
  maintenanceExec = task: "${northRuntimeExec}/bin/north-runtime-exec --chdir --interp ${pkgs.babashka}/bin/bb ${northPkg} cli/coordination-maintenance-task-host.clj ${task}";
in
{
  options.myConfig.modules.north-coordination-workers.enable = lib.mkEnableOption "independently supervised North coordination workers";
  config = lib.mkIf config.myConfig.modules.north-coordination-workers.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-nix-rebuild-worker = {
        Unit = {
          Description = "North Nix rebuild worker";
          ConditionPathExists = rebuildWorker;
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1s";
          Environment = [ rebuildRuntimePath firnBin ];
          WorkingDirectory = promotedRuntime;
          ExecStart = "${pkgs.babashka}/bin/bb ${rebuildWorker}";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.north-concern-reconciliation-worker = {
        Unit = {
          Description = "North durable concern reconciliation worker";
          ConditionPathExists = reconciliationWorker;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1s";
          Environment = [ runtimePath ];
          WorkingDirectory = promotedRuntime;
          ExecStart = "${pkgs.babashka}/bin/bb ${reconciliationWorker} concerns";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.north-attention-reconciliation-worker = {
        Unit = {
          Description = "North attention outbox reconciliation worker";
          ConditionPathExists = reconciliationWorker;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1s";
          Environment = [ runtimePath ];
          WorkingDirectory = promotedRuntime;
          ExecStart = "${pkgs.babashka}/bin/bb ${reconciliationWorker} attention";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.north-coordination-projection-worker = {
        Unit = {
          Description = "North coordination projection worker";
          ConditionPathExists = projectionWorker;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1s";
          Environment = [ runtimePath ];
          WorkingDirectory = promotedRuntime;
          ExecStart = "${pkgs.babashka}/bin/bb ${projectionWorker}";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.north-stale-concern-janitor = {
        Unit = {
          Description = "North stale concern janitor";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = maintenanceExec "stale-concerns";
        };
      };
      systemd.user.timers.north-stale-concern-janitor = {
        Unit = {
          Description = "Run the North stale concern janitor";
        };
        Timer = {
          OnStartupSec = "4m";
          OnUnitInactiveSec = "15m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.north-lane-lifecycle-janitor = {
        Unit = {
          Description = "North lane lifecycle janitor";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = maintenanceExec "stale-lanes";
        };
      };
      systemd.user.timers.north-lane-lifecycle-janitor = {
        Unit = {
          Description = "Run the North lane lifecycle janitor";
        };
        Timer = {
          OnStartupSec = "2m";
          OnUnitInactiveSec = "5m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.north-worktree-janitor = {
        Unit = {
          Description = "North worktree janitor";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = maintenanceExec "worktrees";
        };
      };
      systemd.user.timers.north-worktree-janitor = {
        Unit = {
          Description = "Run the North worktree janitor";
        };
        Timer = {
          OnStartupSec = "6m";
          OnUnitInactiveSec = "15m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.north-agent-log-janitor = {
        Unit = {
          Description = "North agent log janitor";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = maintenanceExec "agent-logs";
        };
      };
      systemd.user.timers.north-agent-log-janitor = {
        Unit = {
          Description = "Run the North agent log janitor";
        };
        Timer = {
          OnStartupSec = "10m";
          OnUnitInactiveSec = "1h";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.north-spend-guard-worker = {
        Unit = {
          Description = "North spend guard worker";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = maintenanceExec "spend-guard";
        };
      };
      systemd.user.timers.north-spend-guard-worker = {
        Unit = {
          Description = "Run the North spend guard worker";
        };
        Timer = {
          OnStartupSec = "45s";
          OnUnitInactiveSec = "1m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
      systemd.user.services.north-runtime-worker-restart = {
        Unit = {
          Description = "Restart long-running North workers after runtime promotion";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${restartRuntimeWorkers}/bin/north-restart-runtime-workers";
        };
      };
      systemd.user.paths.north-runtime-worker-restart = {
        Unit = {
          Description = "Watch the promoted North runtime selector";
        };
        Path = {
          PathChanged = promotedRuntime;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    });
  };
}
