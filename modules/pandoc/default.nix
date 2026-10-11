{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.pandoc.enable {
    "environment" = {
      "systemPackages" = [ pkgs.pandoc ];
    };
  };
  options."myConfig"."modules"."pandoc"."enable" = lib.mkEnableOption "Pandoc document converter";
}
