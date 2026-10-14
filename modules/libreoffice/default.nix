{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.libreoffice;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libreoffice-fresh ]; };
  options.myConfig.modules.libreoffice.enable = lib.mkEnableOption "libreoffice";
}
