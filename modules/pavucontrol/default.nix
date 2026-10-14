{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.pavucontrol;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pavucontrol ]; };
  options.myConfig.modules.pavucontrol.enable = lib.mkEnableOption "PulseAudio volume control";
}
