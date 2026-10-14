{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gutenprint;
in
{
  config = lib.mkIf cfg.enable { services.printing.drivers = [ pkgs.gutenprint ]; };
  options.myConfig.modules.gutenprint.enable = lib.mkEnableOption "Gutenprint printer drivers";
}
