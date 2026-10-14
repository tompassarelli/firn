{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wf-recorder;
in
{
  options.myConfig.modules.wf-recorder.enable = lib.mkEnableOption "Wayland screen recorder";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.wf-recorder ]; };
}
