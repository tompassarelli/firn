{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gpu-screen-recorder.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gpu-screen-recorder ];
    };
  };
  options."myConfig"."modules"."gpu-screen-recorder"."enable" = lib.mkEnableOption "GPU-accelerated screen recorder (X11 + Wayland; NVENC/VAAPI/V4L2)";
}
