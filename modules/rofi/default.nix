{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.rofi;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.rofi
      (pkgs.writeShellScriptBin "rofi-rename-workspace" ''
        name=$(echo "" | rofi -dmenu -p "Rename Workspace")
        [ -n "$name" ] && niri msg action set-workspace-name "$name"

      '')
      (pkgs.writeShellScriptBin "rofi-workspace-switcher" ''
        # Parse niri workspaces: "   1 "name"" or " * 2 "name"" format
        selected=$(niri msg workspaces | grep -E '^\s*\*?\s*[0-9]+' | \
          sed 's/^\s*\*\?\s*\([0-9]\+\)\s*\("\?\)\([^"]*\)\("\?\)/\1: \3/' | \
          sed 's/: $/: (unnamed)/' | \
          rofi -dmenu -p "Workspace" -i)

        [ -n "$selected" ] && {
          id=$(echo "$selected" | cut -d: -f1)
          niri msg action focus-workspace "$id"
        }

      '')
    ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      xdg.configFile."rofi/config.rasi".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/rofi/config.rasi";
    };
  };
  options.myConfig.modules.rofi.enable = lib.mkEnableOption "Rofi application launcher";
}
