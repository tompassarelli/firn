{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wl-gammarelay;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.wl-gammarelay-rs ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      systemd.user.services.wl-gammarelay = {
        Install.WantedBy = [ "niri.service" ];
        Service = {
          BusName = "rs.wl-gammarelay";
          ExecStart = "${builtins.toString pkgs.wl-gammarelay-rs}/bin/wl-gammarelay-rs";
          Restart = "on-failure";
          Type = "dbus";
        };
        Unit = {
          After = [ "graphical-session.target" ];
          Description = "Gamma control for Wayland";
          PartOf = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
      };
      xdg.configFile."wl-gammarelay/temperature-control".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/wl-gammarelay/temperature-control";
    };
  };
  options.myConfig.modules.wl-gammarelay.enable =
    lib.mkEnableOption "Wayland gamma/temperature control";
}
