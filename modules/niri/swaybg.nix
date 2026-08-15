{ config, lib, pkgs, ... }:

((username: ((chosenTheme: {
  config = lib.mkIf config.myConfig.modules.niri.enable {
    home-manager.users.${username} = ({ config, ... }: {
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
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
    });
  };
}) config.myConfig.modules.stylix.chosenTheme)) config.myConfig.modules.users.username)
