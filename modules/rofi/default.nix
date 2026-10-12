{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.rofi.enable {
    "environment" = {
      "systemPackages" = [
        pkgs.rofi
        (pkgs.writeShellScriptBin "rofi-rename-workspace" "name=$(echo \"\" | rofi -dmenu -p \"Rename Workspace\")\n[ -n \"$name\" ] && niri msg action set-workspace-name \"$name\"\n\n")
        (pkgs.writeShellScriptBin "rofi-workspace-switcher" "# Parse niri workspaces: \"   1 \"name\"\" or \" * 2 \"name\"\" format\nselected=$(niri msg workspaces | grep -E '^\\s*\\*?\\s*[0-9]+' | \\\n  sed 's/^\\s*\\*\\?\\s*\\([0-9]\\+\\)\\s*\\(\"\\?\\)\\([^\"]*\\)\\(\"\\?\\)/\\1: \\3/' | \\\n  sed 's/: $/: (unnamed)/' | \\\n  rofi -dmenu -p \"Workspace\" -i)\n\n[ -n \"$selected\" ] && {\n  id=$(echo \"$selected\" | cut -d: -f1)\n  niri msg action focus-workspace \"$id\"\n}\n\n")
      ];
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = hm: {
          "xdg" = {
            "configFile" = {
              "rofi/config.rasi" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/code/nixos-config/dotfiles/rofi/config.rasi");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."rofi"."enable" = lib.mkEnableOption "Rofi application launcher";
}
