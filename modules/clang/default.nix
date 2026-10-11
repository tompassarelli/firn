{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.clang.enable {
    "environment" = {
      "systemPackages" = [ pkgs.clang ];
    };
  };
  options."myConfig"."modules"."clang"."enable" = lib.mkEnableOption "Clang C/C++ compiler";
}
