{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.niri;
  username = config.myConfig.modules.users.username;
  busy = "${config.myConfig.modules.users.homeDir}/.local/share/north/bin/agents-busy";
  idleState = "${config.myConfig.modules.users.homeDir}/.local/share/north/bin/north desktop-idle-state";
  capacity = "${pkgs.bun}/bin/bun ${config.myConfig.modules.users.homeDir}/.claude/skills/machine-capacity/scripts/machine-capacity.mjs mode";
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.swayidle = {
        Unit = {
          Description = "Idle manager for Wayland";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.swayidle}/bin/swayidle -w timeout 60 '${idleState} idle' resume '${idleState} active' timeout 601 '${busy} || niri msg action power-off-monitors' timeout 600 '${busy} || swaylock -f' timeout 600 '${capacity} away >/dev/null' resume '${capacity} present >/dev/null' before-sleep 'swaylock -f'";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "niri.service" ];
      };
    };
  };
}
