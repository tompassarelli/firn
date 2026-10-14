{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.hplip;
in
{
  options.myConfig.modules.hplip.enable = lib.mkEnableOption "HP printer drivers";
  config = lib.mkIf cfg.enable { services.printing.drivers = [ pkgs.hplip ]; };
}
