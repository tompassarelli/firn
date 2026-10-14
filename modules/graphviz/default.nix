{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.graphviz;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.graphviz ]; };
  options.myConfig.modules.graphviz.enable = lib.mkEnableOption "Graphviz graph visualization";
}
