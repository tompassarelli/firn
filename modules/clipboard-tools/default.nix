{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.clipboard-tools.enable = lib.mkEnableOption "Clipboard persistence daemon and X selection diagnostics";
  config = lib.mkIf config.myConfig.modules.clipboard-tools.enable {
    environment.systemPackages = with pkgs; [ wl-clip-persist xclip xsel xlsclients ];
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.wl-clip-persist = {
        Unit = {
          Description = "Keep the Wayland clipboard after the source client exits";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
    });
  };
}
