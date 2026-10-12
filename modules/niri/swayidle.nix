{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  busy = "${config.myConfig.modules.users.homeDir}/.local/share/north/bin/agents-busy";
  capacity = "${pkgs.bun}/bin/bun ${config.myConfig.modules.users.homeDir}/.claude/skills/machine-capacity/scripts/machine-capacity.mjs mode";
in {
  config = lib.mkIf config.myConfig.modules.niri.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.swayidle = {
        Unit = {
          Description = "Idle manager for Wayland";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 601 '${busy} || niri msg action power-off-monitors' timeout 600 '${busy} || swaylock -f' timeout 600 '${capacity} away >/dev/null' resume '${capacity} present >/dev/null' before-sleep 'swaylock -f'";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
    });
  };
}
