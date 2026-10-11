{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.delta.enable {
    "environment" = {
      "systemPackages" = [ pkgs.delta ];
    };
  };
  options."myConfig"."modules"."delta"."enable" = lib.mkEnableOption "delta git diff viewer";
}
