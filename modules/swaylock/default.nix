{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.swaylock;
in
{
  options.myConfig.modules.swaylock.enable = lib.mkEnableOption "swaylock screen locker";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.swaylock ]; };
}
