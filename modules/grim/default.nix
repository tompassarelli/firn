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
  options.myConfig.modules.grim.enable = lib.mkEnableOption "Grim screenshot tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.grim ]; };
}
