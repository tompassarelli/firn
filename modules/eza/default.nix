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
  options.myConfig.modules.eza.enable = lib.mkEnableOption "eza";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.eza ]; };
}
