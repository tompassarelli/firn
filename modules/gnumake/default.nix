{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gnumake.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gnumake ];
    };
  };
  options."myConfig"."modules"."gnumake"."enable" = lib.mkEnableOption "GNU Make build tool";
}
