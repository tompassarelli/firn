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
  options.myConfig.modules.bc.enable = lib.mkEnableOption "bc";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bc ]; };
}
