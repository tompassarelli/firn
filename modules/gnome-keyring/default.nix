{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.gnome-keyring.enable {
    "programs" = {
      "seahorse" = {
        "enable" = true;
      };
    };
    "security" = {
      "pam" = {
        "services" = {
          "login" = {
            "enableGnomeKeyring" = true;
          };
        };
      };
    };
    "services" = {
      "gnome" = {
        "gnome-keyring" = {
          "enable" = true;
        };
      };
    };
  };
  options."myConfig"."modules"."gnome-keyring"."enable" = lib.mkEnableOption "GNOME Keyring (secrets storage + Seahorse GUI)";
}
