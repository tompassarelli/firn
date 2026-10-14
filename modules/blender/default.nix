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
  options.myConfig.modules.blender.enable = lib.mkEnableOption "Blender 3D editor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.blender ]; };
}
