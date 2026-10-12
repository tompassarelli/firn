{ config, lib, pkgs, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
in {
  options.myConfig.modules.update-notify.enable = lib.mkEnableOption "Visible automatic-update failures";
  config = lib.mkIf config.myConfig.modules.update-notify.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services."update-notify@" = {
        Unit = {
          Description = "Report an automatic-update failure";
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/share/firn/bin:${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.libnotify ]}"
          ];
          ExecStart = "${homeDir}/.local/share/firn/bin/update-notify %i";
        };
      };
    });
  };
}
