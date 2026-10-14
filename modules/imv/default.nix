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
  options.myConfig.modules.imv.enable = lib.mkEnableOption "imv image viewer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.imv ]; };
}
