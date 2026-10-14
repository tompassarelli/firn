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
  options.myConfig.modules.libreoffice.enable = lib.mkEnableOption "libreoffice";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libreoffice-fresh ]; };
}
