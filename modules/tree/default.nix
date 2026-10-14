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
  options.myConfig.modules.tree.enable = lib.mkEnableOption "tree";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.tree ]; };
}
