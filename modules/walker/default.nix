{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.myConfig.modules.walker;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.walker.enable = lib.mkEnableOption "Walker modern wayland app launcher";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "walker-rename-workspace" ''
        name=$(echo "" | walker --dmenu)
        [ -n "$name" ] && niri msg action set-workspace-name "$name"

      '')
    ];
    home-manager.users.${username} = _: {
      imports = [ inputs.walker.homeManagerModules.default ];
      home.file.".config/elephant/desktopapplications.toml".text = ''
        # Force proper Wayland env vars when launching apps (fixes Steam on niri)
        launch_prefix = "env WAYLAND_DISPLAY=wayland-1 DISPLAY=:0"

      '';
      programs.walker = {
        enable = true;
        runAsService = true;
        config = {
          hide_quick_activation = true;
          providers = {
            default = [
              "desktopapplications"
              "calc"
              "windows"
            ];
            empty = [ "desktopapplications" ];
          };
          keybinds = {
            quick_activate = [
              "alt a"
              "alt s"
              "alt d"
              "alt f"
              "alt j"
              "alt k"
              "alt l"
              "alt semicolon"
            ];
            next = [
              "Down"
              "ctrl j"
            ];
            previous = [
              "Up"
              "ctrl k"
            ];
          };
          builtins = {
            applications.actions.start.activation_mode = {
              type = "key";
              key = "Return";
            };
            windows.actions = [
              {
                action = "focus";
                bind = "Return";
                default = true;
              }
            ];
            dmenu = {
              hidden = false;
              weight = 5;
              name = "dmenu";
              placeholder = "Rename Workspace";
              switcher_only = false;
              show_icon_when_single = true;
            };
          };
        };
      };
    };
  };
}
