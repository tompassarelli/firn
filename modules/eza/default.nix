{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.eza;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.eza ]; };
  options.myConfig.modules.eza.enable = lib.mkEnableOption "eza";
}
