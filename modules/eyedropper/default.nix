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
  options.myConfig.modules.eyedropper.enable = lib.mkEnableOption "Wayland color picker";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.eyedropper ]; };
}
