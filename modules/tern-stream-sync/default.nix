{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.tern-stream-sync.enable = lib.mkEnableOption "Tern stream-sync timer — periodic transcript log-shipping into streams/raw";
  config = lib.mkIf config.myConfig.modules.tern-stream-sync.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.tern-stream-sync = {
        Unit = {
          Description = "Tern stream-sync — mirror Claude Code transcripts into streams/raw";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${codeDir}/tern/bin/tern-stream-sync";
        };
      };
      systemd.user.timers.tern-stream-sync = {
        Unit = {
          Description = "Run tern-stream-sync periodically";
        };
        Timer = {
          OnStartupSec = "2m";
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
