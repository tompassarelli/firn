{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.slurp.enable {
    "environment" = {
      "systemPackages" = [ pkgs.slurp ];
    };
  };
  options."myConfig"."modules"."slurp"."enable" = lib.mkEnableOption "Wayland region selector";
}
