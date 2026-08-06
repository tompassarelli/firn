{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  monoFont = config.stylix.fonts.monospace.name;
in
{
  options.myConfig.modules.quickshell.enable = lib.mkEnableOption "Quickshell (Qt6/QML) status bar";
  config = lib.mkIf config.myConfig.modules.quickshell.enable {
    environment.systemPackages = [ inputs.quickshell.packages."${pkgs.stdenv.hostPlatform.system}".default ];
    users.users.${username}.extraGroups = [ "input" ];
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.quickshell = {
        Unit = {
          Description = "Quickshell widget framework";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${inputs.quickshell.packages."${pkgs.stdenv.hostPlatform.system}".default}/bin/qs";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "niri.service" ];
        };
      };
      xdg.configFile = {
        "quickshell/shell.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/shell.qml";
        "quickshell/Bar.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/Bar.qml";
        "quickshell/NiriListener.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/NiriListener.qml";
        "quickshell/BarState.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/BarState.qml";
        "quickshell/WorkspaceRow.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/WorkspaceRow.qml";
        "quickshell/SpacesState.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/SpacesState.qml";
        "quickshell/WorkspacePopup.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/WorkspacePopup.qml";
        "quickshell/key-release-monitor.py".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/key-release-monitor.py";
        "quickshell/LayoutConfig.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/LayoutConfig.qml";
        "quickshell/NotificationPopup.qml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/quickshell/NotificationPopup.qml";
        "quickshell/StylixColors.qml".text = with config.lib.stylix.colors; ''
          import QtQuick

          QtObject {
              readonly property color base00: "#${base00}"
              readonly property color base01: "#${base01}"
              readonly property color base02: "#${base02}"
              readonly property color base03: "#${base03}"
              readonly property color base04: "#${base04}"
              readonly property color base05: "#${base05}"
              readonly property color base06: "#${base06}"
              readonly property color base07: "#${base07}"
              readonly property color base08: "#${base08}"
              readonly property color base09: "#${base09}"
              readonly property color base0A: "#${base0A}"
              readonly property color base0B: "#${base0B}"
              readonly property color base0C: "#${base0C}"
              readonly property color base0D: "#${base0D}"
              readonly property color base0E: "#${base0E}"
              readonly property color base0F: "#${base0F}"
              readonly property string fontFamily: "${monoFont}"
          }

        '';
      };
    });
  };
}
