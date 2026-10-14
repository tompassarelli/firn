{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.grim;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.grim ]; };
  options.myConfig.modules.grim.enable = lib.mkEnableOption "Grim screenshot tool";
}
