{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bc;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bc ]; };
  options.myConfig.modules.bc.enable = lib.mkEnableOption "bc";
}
