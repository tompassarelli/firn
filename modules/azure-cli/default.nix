{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.azure-cli.enable {
    "environment" = {
      "systemPackages" = [ pkgs.azure-cli ];
    };
  };
  options."myConfig"."modules"."azure-cli"."enable" = lib.mkEnableOption "Azure CLI (az) for Entra / Microsoft Graph admin";
}
