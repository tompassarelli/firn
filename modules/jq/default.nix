{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.jq.enable {
    "environment" = {
      "systemPackages" = [ pkgs.jq ];
    };
  };
  options."myConfig"."modules"."jq"."enable" = lib.mkEnableOption "jq command-line JSON processor";
}
