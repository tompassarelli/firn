{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.myConfig.modules.slippi;
  slippiPackages = inputs.slippi.packages.${pkgs.stdenv.hostPlatform.system};
  launcher = slippiPackages.slippi-launcher-desktop;
  desktopItem = pkgs.makeDesktopItem {
    name = "slippi-launcher";
    desktopName = "Slippi Launcher";
    comment = "Launch Slippi Online, browse and watch saved replays";
    exec = "${lib.getExe launcher} %U";
    icon = "${slippiPackages.slippi-launcher}/share/icons/hicolor/512x512/apps/slippi-launcher.png";
    categories = [ "Game" ];
    mimeTypes = [ "x-scheme-handler/slippi" ];
    startupWMClass = "Slippi Launcher";
  };
in
{
  options.myConfig.modules.slippi.enable =
    lib.mkEnableOption "Slippi Launcher with Nix-built netplay and playback Dolphin";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      launcher
      desktopItem
    ];
    services.udev.extraRules = ''
      ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0337", MODE="666", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device" TAG+="uaccess"
    '';
  };
}
