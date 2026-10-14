{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wine;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wineWowPackages.unstable
      pkgs.unstable.winetricks
    ];
  };
  options.myConfig.modules.wine.enable = lib.mkEnableOption "Wine (unstable, 32+64-bit)";
}
