{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.btop.enable {
    "environment" = {
      "systemPackages" = [ pkgs.btop ];
    };
  };
  options.myConfig.modules.btop.enable = lib.mkEnableOption "btop";
}
