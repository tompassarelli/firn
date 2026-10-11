{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.networking.enable {
    "environment" = {
      "systemPackages" = [ pkgs.networkmanagerapplet ];
    };
    "networking" = {
      "networkmanager" = {
        "enable" = true;
        "logLevel" = "DEBUG";
        "unmanaged" = [ "interface-name:wg*" ];
        "wifi" = {
          "powersave" = false;
        };
      };
    };
  };
  options."myConfig"."modules"."networking"."enable" = lib.mkEnableOption "network configuration";
}
