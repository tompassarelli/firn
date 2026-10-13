{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.bluetooth.enable {
    "environment" = {
      "systemPackages" = [ pkgs.bluez ];
    };
    "hardware" = {
      "bluetooth" = {
        "enable" = true;
        "powerOnBoot" = true;
        "settings" = {
          "General" = {
            "Enable" = "Source,Sink,Media,Socket";
            "Experimental" = true;
          };
        };
      };
    };
    "services" = {
      "blueman" = {
        "enable" = true;
      };
    };
  };
  options.myConfig.modules.bluetooth.enable = lib.mkEnableOption "bluetooth";
}
