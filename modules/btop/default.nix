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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.btop ]; };
  options.myConfig.modules.btop.enable = lib.mkEnableOption "btop";
}
