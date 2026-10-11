{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.eyedropper.enable {
    "environment" = {
      "systemPackages" = [ pkgs.eyedropper ];
    };
  };
  options."myConfig"."modules"."eyedropper"."enable" = lib.mkEnableOption "Wayland color picker";
}
