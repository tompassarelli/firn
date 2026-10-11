{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.fd.enable {
    "environment" = {
      "systemPackages" = [ pkgs.fd ];
    };
  };
  options."myConfig"."modules"."fd"."enable" = lib.mkEnableOption "fd file finder";
}
