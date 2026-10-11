{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.graphviz.enable {
    "environment" = {
      "systemPackages" = [ pkgs.graphviz ];
    };
  };
  options."myConfig"."modules"."graphviz"."enable" = lib.mkEnableOption "Graphviz graph visualization";
}
