{ config, lib, ... }:
let
  cfg = config.myConfig.modules.via;
in
{
  options.myConfig.modules.via.enable = lib.mkEnableOption "VIA keyboard configurator support";
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # VIA keyboard access rules
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="plugdev", TAG+="uaccess"

      # Additional rules for QMK/VIA keyboards
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="c2ab", ATTRS{idProduct}=="3939", TAG+="uaccess"

    '';
    users = {
      groups.plugdev = { };
      users.${config.myConfig.modules.users.username}.extraGroups = [ "plugdev" ];
    };
  };
}
