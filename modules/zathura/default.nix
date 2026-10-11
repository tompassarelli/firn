{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.zathura.enable {
    "environment" = {
      "systemPackages" = [ pkgs.zathura ];
    };
  };
  options."myConfig"."modules"."zathura"."enable" = lib.mkEnableOption "Zathura PDF viewer";
}
