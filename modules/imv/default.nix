{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.imv;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.imv ]; };
  options.myConfig.modules.imv.enable = lib.mkEnableOption "imv image viewer";
}
