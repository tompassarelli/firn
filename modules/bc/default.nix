{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.bc.enable {
    "environment" = {
      "systemPackages" = [ pkgs.bc ];
    };
  };
  options.myConfig.modules.bc.enable = lib.mkEnableOption "bc";
}
