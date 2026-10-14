{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gh;
in
{
  options.myConfig.modules.gh.enable = lib.mkEnableOption "GitHub CLI";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gh ]; };
}
