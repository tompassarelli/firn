{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.godot.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.godot_4 ];
    };
  };
  options."myConfig"."modules"."godot"."enable" = lib.mkEnableOption "Godot game engine";
}
