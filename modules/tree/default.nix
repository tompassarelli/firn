{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.tree.enable {
    "environment" = {
      "systemPackages" = [ pkgs.tree ];
    };
  };
  options.myConfig.modules.tree.enable = lib.mkEnableOption "tree";
}
