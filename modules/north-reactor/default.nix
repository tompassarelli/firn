{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
in
{
  options.myConfig.modules.north-reactor.enable = lib.mkEnableOption "North reactor sweep timer — periodic liveness reap of stale concerns + silently-dead lanes";
  config = lib.mkIf config.myConfig.modules.north-reactor.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-reactor-sweep = {
        Unit = {
          Description = "North reactor sweep — reap stale concerns + silently-dead lanes";
          X-SwitchMethod = "keep-old";
        };
        restartIfChanged = false;
        Service = {
          Type = "oneshot";
          Environment = [ "PATH=${pkgs.babashka}/bin:${pkgs.coreutils}/bin:${pkgs.git}/bin" ];
          WorkingDirectory = northPkg;
          ExecStart = "${pkgs.babashka}/bin/bb ${northPkg}/cli/north-reactor.clj sweep-once";
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
