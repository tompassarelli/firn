{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.uv.enable {
    "environment" = {
      "systemPackages" = [ pkgs.uv ];
    };
  };
  options."myConfig"."modules"."uv"."enable" = lib.mkEnableOption "uv Python package manager";
}
