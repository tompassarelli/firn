{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.ripgrep.enable {
    "environment" = {
      "systemPackages" = [ pkgs.ripgrep ];
    };
  };
  options."myConfig"."modules"."ripgrep"."enable" = lib.mkEnableOption "ripgrep search tool";
}
