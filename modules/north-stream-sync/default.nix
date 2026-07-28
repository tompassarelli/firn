{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
in
{
  options.myConfig.modules.north-stream-sync.enable = lib.mkEnableOption "North stream-sync timer — periodic transcript log-shipping into streams/raw";
  config = lib.mkIf config.myConfig.modules.north-stream-sync.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.north-stream-sync = {
        Unit = {
          Description = "North stream-sync — mirror Claude Code transcripts into streams/raw";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          SuccessExitStatus = "2";
          ExecStart = "${northPkg}/bin/north-stream-sync-all";
        };
      };
      systemd.user.timers.north-stream-sync = {
        Unit = {
          Description = "Run north-stream-sync periodically";
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
    });
  };
}
