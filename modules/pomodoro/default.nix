{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.pomodoro;
in
{
  options.myConfig.modules.pomodoro.enable = lib.mkEnableOption "Pomodoro timer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pomodoro-gtk ]; };
}
