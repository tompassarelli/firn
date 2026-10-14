{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gpu-screen-recorder;
in
{
  options.myConfig.modules.gpu-screen-recorder.enable =
    lib.mkEnableOption "GPU-accelerated screen recorder (X11 + Wayland; NVENC/VAAPI/V4L2)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gpu-screen-recorder ]; };
}
