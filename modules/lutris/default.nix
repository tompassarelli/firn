{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.lutris.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.lutris ];
    };
  };
  options."myConfig"."modules"."lutris"."enable" = lib.mkEnableOption "Lutris gaming platform";
}
