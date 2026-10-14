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
  options.myConfig.modules.ripgrep.enable = lib.mkEnableOption "ripgrep search tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.ripgrep ]; };
}
