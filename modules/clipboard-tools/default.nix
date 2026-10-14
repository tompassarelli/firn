{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.clipboard-tools;
in
{
  options.myConfig.modules.clipboard-tools.enable =
    lib.mkEnableOption "Clipboard persistence daemon and X selection diagnostics";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wl-clip-persist
      pkgs.xlsclients
    ];
    home-manager.users.${config.myConfig.modules.users.username} = _hm: {
      systemd.user.services.wl-clip-persist = {
        Install.WantedBy = [ "niri.service" ];
        Service = {
          ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
          Restart = "on-failure";
        };
        Unit = {
          After = [ "graphical-session.target" ];
          Description = "Keep the Wayland clipboard after the source client exits";
          PartOf = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
      };
    };
  };
}
