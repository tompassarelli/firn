{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  codeDir = config.myConfig.modules.users.codeDir;
in
{
  options.myConfig.modules.north-stream-sync.enable = lib.mkEnableOption "North stream-sync timer — periodic transcript log-shipping into streams/raw";
  config = lib.mkIf config.myConfig.modules.north-stream-sync.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-stream-sync = {
        Unit = {
          Description = "North stream-sync — mirror Claude Code transcripts into streams/raw";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${codeDir}/north/bin/north-stream-sync";
        };
      };
      systemd.user.timers.north-stream-sync = {
        Unit = {
          Description = "Run north-stream-sync periodically";
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
