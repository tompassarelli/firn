{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.unrar;
in
{
  options.myConfig.modules.unrar.enable = lib.mkEnableOption "unrar archive tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unrar ]; };
}
