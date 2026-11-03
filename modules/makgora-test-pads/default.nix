{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.makgora-test-pads;
in
{
  options.myConfig.modules.makgora-test-pads.enable =
    lib.mkEnableOption "Mak'gora test pads: hidden from Steam and the desktop, readable by the test helpers";
  config = lib.mkIf cfg.enable {
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/69-makgora-test-pads.rules" ''
        ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event*|js*", ATTRS{name}=="Makgora Event Retention Virtual Gamepad", ENV{ID_INPUT_JOYSTICK}="", GROUP:="root", MODE:="0600"
        ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Makgora Event Retention Virtual Gamepad", ENV{MAKGORA_TEST_PAD_NODE}="/dev/makgora-pads/%k", RUN+="${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/mkdir -p /dev/makgora-pads && ${pkgs.coreutils}/bin/rm -f /dev/makgora-pads/.%k && ${pkgs.coreutils}/bin/mknod -m 0660 /dev/makgora-pads/.%k c $major $minor && ${pkgs.coreutils}/bin/chgrp input /dev/makgora-pads/.%k && ${pkgs.coreutils}/bin/mv -f /dev/makgora-pads/.%k /dev/makgora-pads/%k'"
        ACTION=="remove", SUBSYSTEM=="input", KERNEL=="event*", ENV{MAKGORA_TEST_PAD_NODE}=="?*", RUN+="${pkgs.coreutils}/bin/rm -f $env{MAKGORA_TEST_PAD_NODE}"
      '')
    ];
  };
}
