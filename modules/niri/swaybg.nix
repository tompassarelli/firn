{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.niri;
  username = config.myConfig.modules.users.username;
  chosenTheme = config.myConfig.modules.stylix.chosenTheme;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.swaybg = {
        Unit = {
          Description = "Wayland wallpaper tool";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.swaybg}/bin/swaybg -i \"$(${pkgs.fd}/bin/fd -t f . $HOME/.config/themes/${chosenTheme}/wallpapers/ | ${pkgs.coreutils}/bin/shuf -n 1)\" --mode fill'";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "niri.service" ];
      };
    };
  };
}
