{ config, lib, pkgs, ... }:

((username: ((chosenTheme: ((schemeFile: ((schemeYaml: ((variant: {
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
}) (((lines: ((variantLine: ((match: if (match != null) then builtins.head match else "dark") (builtins.match ".*variant: \"([^\"]+)\".*" variantLine))) (lib.findFirst (line: lib.hasPrefix "variant:" line) "" lines))) (lib.splitString "\n" schemeYaml))))) (builtins.readFile schemeFile))) "${pkgs.base16-schemes}/share/themes/${chosenTheme}.yaml")) config.myConfig.modules.stylix.chosenTheme)) config.myConfig.modules.users.username)
