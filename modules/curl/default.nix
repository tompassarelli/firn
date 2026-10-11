{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.curl.enable {
    "environment" = {
      "systemPackages" = [ pkgs.curl ];
    };
  };
  options."myConfig"."modules"."curl"."enable" = lib.mkEnableOption "curl HTTP client";
}
