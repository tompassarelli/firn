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
  options.myConfig.modules.hugo.enable = lib.mkEnableOption "Hugo static site generator";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.hugo ]; };
}
