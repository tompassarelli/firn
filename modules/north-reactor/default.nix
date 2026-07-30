{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  northRuntimeExec = pkgs.writeShellApplication {
    name = "north-runtime-exec";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../north/north-runtime-exec;
  };
in
{
  options.myConfig.modules.north-reactor.enable = lib.mkEnableOption "North reactor — supervised reprojection/window-owner loop plus the periodic liveness sweep";
  config = lib.mkIf config.myConfig.modules.north-reactor.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-reactor = {
        Unit = {
          Description = "North reactor — thread reprojection, liveness sweep, rebuild-window owner";
          After = [ "network.target" ];
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "simple";
          Environment = [ "PATH=${pkgs.systemd}/bin:${pkgs.git}/bin:${pkgs.coreutils}/bin" ];
          WorkingDirectory = "${config.home.homeDirectory}/code/north/main";
          ExecStart = "${northRuntimeExec}/bin/north-runtime-exec ${northPkg} bin/north reactor 7977";
          Restart = "always";
          RestartSec = 5;
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
          Environment = [
            "PATH=${pkgs.systemd}/bin:${pkgs.babashka}/bin:${pkgs.coreutils}/bin:${pkgs.git}/bin"
          ];
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
