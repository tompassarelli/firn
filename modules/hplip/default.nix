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
  config = lib.mkIf cfg.enable { services.printing.drivers = [ pkgs.hplip ]; };
  options.myConfig.modules.hplip.enable = lib.mkEnableOption "HP printer drivers";
}
