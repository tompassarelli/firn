{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.hugo.enable {
    "environment" = {
      "systemPackages" = [ pkgs.hugo ];
    };
  };
  options."myConfig"."modules"."hugo"."enable" = lib.mkEnableOption "Hugo static site generator";
}
