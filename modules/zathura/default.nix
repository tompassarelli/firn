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
  options.myConfig.modules.zathura.enable = lib.mkEnableOption "Zathura PDF viewer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.zathura ]; };
}
