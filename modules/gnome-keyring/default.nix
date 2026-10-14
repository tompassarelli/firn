{ config, lib, ... }:
let
  cfg = config.myConfig.modules.gnome-keyring;
in
{
  options.myConfig.modules.gnome-keyring.enable =
    lib.mkEnableOption "GNOME Keyring (secrets storage + Seahorse GUI)";
  config = lib.mkIf cfg.enable {
    programs.seahorse.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
    services.gnome.gnome-keyring.enable = true;
  };
}
