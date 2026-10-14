{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bevy;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.alsa-lib
      pkgs.vulkan-loader
      pkgs.vulkan-tools
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.xorg.libX11
      pkgs.xorg.libXcursor
      pkgs.xorg.libXrandr
      pkgs.xorg.libXi
      pkgs.libudev-zero
    ];
    programs.nix-ld.libraries = [
      pkgs.alsa-lib
      pkgs.vulkan-loader
      pkgs.vulkan-tools
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.xorg.libX11
      pkgs.xorg.libXcursor
      pkgs.xorg.libXrandr
      pkgs.xorg.libXi
      pkgs.libudev-zero
    ];
  };
  options.myConfig.modules.bevy.enable = lib.mkEnableOption "Bevy game engine development libraries";
}
