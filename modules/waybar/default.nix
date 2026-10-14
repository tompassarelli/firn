{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.waybar;
in
{
  options.myConfig.modules.waybar.enable = lib.mkEnableOption "Waybar status bar for Wayland";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.waybar ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      systemd.user.services = {
        waybar = {
          Install.WantedBy = [ "niri.service" ];
          Service = {
            ExecStart = "${pkgs.waybar}/bin/waybar";
            Restart = "on-failure";
          };
          Unit = {
            After = [
              "graphical-session.target"
              "xdg-desktop-portal.service"
            ];
            Description = "Highly customizable Wayland bar";
            PartOf = [ "graphical-session.target" ];
            Requisite = [ "graphical-session.target" ];
          };
        };
        waybar-overview = {
          Install.WantedBy = [ "niri.service" ];
          Service = {
            ExecStart = "%h/.config/waybar/overview-waybar.py";
            Restart = "on-failure";
          };
          Unit = {
            After = [ "waybar.service" ];
            Description = "Waybar visibility controller (overview + workspace switch)";
            PartOf = [ "graphical-session.target" ];
            Requires = [ "waybar.service" ];
          };
        };
      };
      xdg.configFile = {
        "waybar/config".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/waybar/config";
        "waybar/overview-waybar.py".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/waybar/overview-waybar.py";
        "waybar/style.css".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/waybar/style.css";
        "waybar/stylix.css".text = ''
          @define-color base00 #${hm.config.lib.stylix.colors.base00};
          @define-color base01 #${hm.config.lib.stylix.colors.base01};
          @define-color base02 #${hm.config.lib.stylix.colors.base02};
          @define-color base03 #${hm.config.lib.stylix.colors.base03};
          @define-color base04 #${hm.config.lib.stylix.colors.base04};
          @define-color base05 #${hm.config.lib.stylix.colors.base05};
          @define-color base06 #${hm.config.lib.stylix.colors.base06};
          @define-color base07 #${hm.config.lib.stylix.colors.base07};
          @define-color base08 #${hm.config.lib.stylix.colors.base08};
          @define-color base09 #${hm.config.lib.stylix.colors.base09};
          @define-color base0A #${hm.config.lib.stylix.colors.base0A};
          @define-color base0B #${hm.config.lib.stylix.colors.base0B};
          @define-color base0C #${hm.config.lib.stylix.colors.base0C};
          @define-color base0D #${hm.config.lib.stylix.colors.base0D};
          @define-color base0E #${hm.config.lib.stylix.colors.base0E};
          @define-color base0F #${hm.config.lib.stylix.colors.base0F};

          * {
            font-family: "${hm.config.stylix.fonts.monospace.name}";
            font-size: ${builtins.toString hm.config.stylix.fonts.sizes.desktop}pt;
          }

          window#waybar, tooltip {
            background: alpha(@base00, ${builtins.toString hm.config.stylix.opacity.desktop});
            color: @base05;
          }

          tooltip {
            border-color: @base0D;
          }

          .modules-left #workspaces button {
            border-bottom: 3px solid transparent;
          }
          .modules-left #workspaces button.focused,
          .modules-left #workspaces button.active {
            border-bottom: 3px solid @base05;
          }

          .modules-center #workspaces button {
            border-bottom: 3px solid transparent;
          }
          .modules-center #workspaces button.focused,
          .modules-center #workspaces button.active {
            border-bottom: 3px solid @base05;
          }

          .modules-right #workspaces button {
            border-bottom: 3px solid transparent;
          }
          .modules-right #workspaces button.focused,
          .modules-right #workspaces button.active {
            border-bottom: 3px solid @base05;
          }

        '';
      };
    };
  };
}
