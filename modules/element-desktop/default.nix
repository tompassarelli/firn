{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.element-desktop;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.element-desktop.override { commandLineArgs = "--password-store=gnome-libsecret"; })
    ];
  };
  options.myConfig.modules.element-desktop.enable =
    lib.mkEnableOption "Element Matrix desktop client";
}
