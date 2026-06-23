{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.azure-cli.enable = lib.mkEnableOption "Azure CLI (az) for Entra / Microsoft Graph admin";
  config = lib.mkIf config.myConfig.modules.azure-cli.enable {
    environment.systemPackages = with pkgs; [ azure-cli ];
  };
}
