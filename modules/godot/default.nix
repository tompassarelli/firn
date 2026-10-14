{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.godot;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.godot_4 ]; };
  options.myConfig.modules.godot.enable = lib.mkEnableOption "Godot game engine";
}
