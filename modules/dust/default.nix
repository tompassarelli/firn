{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.dust.enable {
    "environment" = {
      "systemPackages" = [ pkgs.dust ];
    };
  };
  options."myConfig"."modules"."dust"."enable" = lib.mkEnableOption "Enable dust disk usage analyzer";
}
