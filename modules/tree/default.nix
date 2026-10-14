{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.tree;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.tree ]; };
  options.myConfig.modules.tree.enable = lib.mkEnableOption "tree";
}
