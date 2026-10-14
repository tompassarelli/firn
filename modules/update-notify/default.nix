{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.update-notify;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  nexusNotify = pkgs.writeShellScript "update-notify-nexus" ''
    set -eu
    unit=$1
    unit=''${unit%.service}.service
    exec ${pkgs.systemd}/bin/systemctl --user start "nexus-notify@$unit.service"
  '';
  notify =
    if config.myConfig.modules.nexus-alerts.enable then
      "${nexusNotify} %i"
    else
      "${homeDir}/.local/share/firn/bin/update-notify %i";
in
{
  options.myConfig.modules.update-notify.enable =
    lib.mkEnableOption "Visible automatic-update failures";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services."update-notify@" = {
        Unit.Description = "Report an automatic-update failure";
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/share/firn/bin:${
              lib.makeBinPath [
                pkgs.bash
                pkgs.coreutils
                pkgs.libnotify
              ]
            }"
          ];
          ExecStart = notify;
        };
      };
    };
  };
}
