{ config, lib, ... }:
let
  cfg = config.myConfig.modules.flatpak;
in
{
  options.myConfig.modules.flatpak.enable = lib.mkEnableOption "Flatpak application runtime";
  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;
  };
}
