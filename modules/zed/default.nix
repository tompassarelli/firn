{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.zed.enable {
    "environment" = {
      "systemPackages" = [ pkgs.zed-editor ];
    };
  };
  options."myConfig"."modules"."zed"."enable" = lib.mkEnableOption "Zed editor";
}
