{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.hugo;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.hugo ]; };
  options.myConfig.modules.hugo.enable = lib.mkEnableOption "Hugo static site generator";
}
