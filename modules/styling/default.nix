{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  chosenTheme = config.myConfig.modules.stylix.chosenTheme;
  schemeFile = "${pkgs.base16-schemes}/share/themes/${chosenTheme}.yaml";
  schemeYaml = builtins.readFile schemeFile;
  variant = let
    lines = lib.splitString "\n" schemeYaml;
    variantLine = lib.findFirst (line: lib.hasPrefix "variant:" line) "" lines;
    match = builtins.match ".*variant: \"([^\"]+)\".*" variantLine;
  in
  if (match != null) then builtins.head match else "dark";
in
{
  options.myConfig.modules.styling.enable = lib.mkEnableOption "system-wide theming and styling";
  config = lib.mkIf config.myConfig.modules.styling.enable {
    stylix = {
      enable = true;
      base16Scheme = schemeFile;
      polarity = variant;
      fonts = {
        monospace = {
          package = pkgs.commit-mono;
          name = "CommitMono";
        };
        sansSerif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs.ia-writer-quattro;
          name = "iA Writer Quattro S";
        };
        sizes = {
          terminal = 14;
        };
      };
    };
    home-manager.users.${username} = ({ config, ... }: {
      stylix.targets.firefox = {
        profileNames = [ username ];
        colorTheme.enable = true;
      };
      xdg.configFile."themes".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/themes";
    });
  };
}
