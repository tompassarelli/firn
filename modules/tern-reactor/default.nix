{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.tern-reactor.enable = lib.mkEnableOption "Tern reactor sweep timer — periodic liveness reap of stale concerns + silently-dead lanes";
  config = lib.mkIf config.myConfig.modules.tern-reactor.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.tern-reactor-sweep = {
        Unit = {
          Description = "Tern reactor sweep — reap stale concerns + silently-dead lanes";
        };
        Service = {
          Type = "oneshot";
          Environment = [ "PATH=${pkgs.babashka}/bin:${pkgs.coreutils}/bin" ];
          WorkingDirectory = "${codeDir}/tern";
          ExecStart = "${pkgs.babashka}/bin/bb ${codeDir}/tern/cli/tern-reactor.clj sweep-once";
        };
      };
      systemd.user.timers.tern-reactor-sweep = {
        Unit = {
          Description = "Run the tern reactor liveness sweep periodically";
        };
        Timer = {
          OnStartupSec = "3m";
          OnUnitActiveSec = "5m";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}
