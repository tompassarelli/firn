{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.ladybird.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.ladybird ];
    };
  };
  options."myConfig"."modules"."ladybird"."enable" = lib.mkEnableOption "Enable Ladybird browser (bleeding edge from git)";
}
