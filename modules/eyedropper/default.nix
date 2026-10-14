{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.eyedropper;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.eyedropper ]; };
  options.myConfig.modules.eyedropper.enable = lib.mkEnableOption "Wayland color picker";
}
