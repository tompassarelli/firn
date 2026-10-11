{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.via.enable {
    "services" = {
      "udev" = {
        "extraRules" = "# VIA keyboard access rules\nKERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", MODE=\"0660\", GROUP=\"plugdev\", TAG+=\"uaccess\"\n\n# Additional rules for QMK/VIA keyboards\nSUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"c2ab\", ATTRS{idProduct}==\"3939\", TAG+=\"uaccess\"\n\n";
      };
    };
    "users" = {
      "groups" = {
        "plugdev" = { };
      };
      "users" = {
        ${config.myConfig.modules.users.username} = {
          "extraGroups" = [ "plugdev" ];
        };
      };
    };
  };
  options."myConfig"."modules"."via"."enable" = lib.mkEnableOption "VIA keyboard configurator support";
}
