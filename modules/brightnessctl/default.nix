{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.brightnessctl;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.brightnessctl ]; };
  options.myConfig.modules.brightnessctl.enable = lib.mkEnableOption "screen brightness control";
}
