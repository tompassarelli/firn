{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  runtimePath = "PATH=${pkgs.systemd}/bin:${pkgs.babashka}/bin:${pkgs.coreutils}/bin:${pkgs.git}/bin";
  northRuntimeExec = pkgs.writeShellApplication {
    name = "north-runtime-exec";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../north/north-runtime-exec;
  };
in
{
  options.myConfig.modules.north-reactor.enable = lib.mkEnableOption "North reactor periodic liveness and rebuild-window sweep";
  options.myConfig.modules.north-reactor.eventOwner.enable = lib.mkEnableOption "North event-driven rebuild queue owner. OFF until cursor-only writes stop waking the watcher: it self-triggered at ~30 wakes/s on zero real events. A hand-placed /dev/null mask cannot express this — it collides with the unit HM writes and aborts activation";
  config = lib.mkIf config.myConfig.modules.north-reactor.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-rebuild-queue-owner = lib.mkIf config.myConfig.modules.north-reactor.eventOwner.enable {
        Unit = {
          Description = "North event-driven rebuild queue owner";
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1s";
          Environment = [ runtimePath ];
          ExecStart = "${northRuntimeExec}/bin/north-runtime-exec --chdir --interp ${pkgs.babashka}/bin/bb ${northPkg} cli/rebuild-window-watch.clj";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.north-reactor-sweep = {
        Unit = {
          Description = "North reactor sweep — reap stale concerns + silently-dead lanes";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          Environment = [ runtimePath ];
          ExecStart = "${northRuntimeExec}/bin/north-runtime-exec --chdir --interp ${pkgs.babashka}/bin/bb ${northPkg} cli/north-reactor.clj sweep-once";
        };
      };
      systemd.user.timers.north-reactor-sweep = {
        Unit = {
          Description = "Run the north reactor liveness sweep periodically";
        };
        Timer = {
          OnStartupSec = "3m";
          OnUnitInactiveSec = "5m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}
