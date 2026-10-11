{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.blender.enable {
    "environment" = {
      "systemPackages" = [ pkgs.blender ];
    };
  };
  options."myConfig"."modules"."blender"."enable" = lib.mkEnableOption "Blender 3D editor";
}
