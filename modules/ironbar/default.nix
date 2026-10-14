{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ironbar;
in
{
  options.myConfig.modules.ironbar.enable = lib.mkEnableOption "Ironbar status bar for Wayland";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.unstable.ironbar ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      systemd.user.services = {
        ironbar = {
          Install.WantedBy = [ "niri.service" ];
          Service = {
            ExecStart = "${pkgs.unstable.ironbar}/bin/ironbar";
            Restart = "on-failure";
          };
          Unit = {
            After = [ "graphical-session.target" ];
            Description = "Customizable GTK4 status bar for Wayland";
            PartOf = [ "graphical-session.target" ];
            Requisite = [ "graphical-session.target" ];
          };
        };
        ironbar-overview = {
          Install.WantedBy = [ "niri.service" ];
          Service = {
            ExecStart = "%h/.config/ironbar/overview-ironbar.py";
            Restart = "on-failure";
          };
          Unit = {
            After = [ "ironbar.service" ];
            Description = "Ironbar overview listener script";
            PartOf = [ "graphical-session.target" ];
            Requires = [ "ironbar.service" ];
          };
        };
      };
      xdg.configFile = {
        "ironbar/battery.sh".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/ironbar/battery.sh";
        "ironbar/config.toml".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/ironbar/config.toml";
        "ironbar/overview-ironbar.py".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/ironbar/overview-ironbar.py";
        "ironbar/style.css".source =
          hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/ironbar/style.css";
        "ironbar/stylix.css".text = ''
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

          .background {
            background: alpha(@base00, ${builtins.toString hm.config.stylix.opacity.desktop});
            color: @base05;
          }

          tooltip {
            background: alpha(@base00, ${builtins.toString hm.config.stylix.opacity.desktop});
            color: @base05;
            border-color: @base0D;
          }

        '';
      };
    };
  };
}
