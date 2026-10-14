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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gh ]; };
  options.myConfig.modules.gh.enable = lib.mkEnableOption "GitHub CLI";
}
