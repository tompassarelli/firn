{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.blender;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.blender ]; };
  options.myConfig.modules.blender.enable = lib.mkEnableOption "Blender 3D editor";
}
