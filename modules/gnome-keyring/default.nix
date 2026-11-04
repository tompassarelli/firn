{
  config,
  lib,
  ...
}:
let
  cfg = config.myConfig.modules.gnome-keyring;
  login = config.security.pam.services.login.rules.session;
in
{
  options.myConfig.modules.gnome-keyring.enable =
    lib.mkEnableOption "GNOME Keyring (secrets storage + Seahorse GUI)";
  config = lib.mkIf cfg.enable {
    programs.seahorse.enable = true;
    security.pam.services.login = {
      enableGnomeKeyring = true;
      rules.session.gnome_keyring_terminal_only = {
        order = login.gnome_keyring.order - 1;
        control = "[success=ok default=1]";
        modulePath = "${config.security.pam.package}/lib/security/pam_succeed_if.so";
        args = [
          "quiet"
          "tty"
          "=~"
          "*tty*"
        ];
      };
    };
    services.gnome.gnome-keyring.enable = true;
  };
}
