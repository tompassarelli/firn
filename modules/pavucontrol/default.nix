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
  options.myConfig.modules.pavucontrol.enable = lib.mkEnableOption "PulseAudio volume control";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pavucontrol ]; };
}
