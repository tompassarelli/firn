{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.glow;
in
{
  options.myConfig.modules.glow.enable =
    lib.mkEnableOption "glow — terminal markdown renderer (tables, pager, dir browser)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.glow ]; };
}
