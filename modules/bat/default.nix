{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bat;
in
{
  options.myConfig.modules.bat.enable = lib.mkEnableOption "bat syntax-highlighting cat";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bat ]; };
}
