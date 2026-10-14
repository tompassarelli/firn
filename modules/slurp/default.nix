{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.slurp;
in
{
  options.myConfig.modules.slurp.enable = lib.mkEnableOption "Wayland region selector";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.slurp ]; };
}
