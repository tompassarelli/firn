{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ripgrep;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ripgrep ]; };
  options.myConfig.modules.ripgrep.enable = lib.mkEnableOption "ripgrep search tool";
}
