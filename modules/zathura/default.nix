{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.zathura;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.zathura ]; };
  options.myConfig.modules.zathura.enable = lib.mkEnableOption "Zathura PDF viewer";
}
