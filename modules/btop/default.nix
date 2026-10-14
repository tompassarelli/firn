{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.btop;
in
{
  options.myConfig.modules.btop.enable = lib.mkEnableOption "btop";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.btop ]; };
}
