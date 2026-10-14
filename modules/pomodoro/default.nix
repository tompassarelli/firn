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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pomodoro-gtk ]; };
  options.myConfig.modules.pomodoro.enable = lib.mkEnableOption "Pomodoro timer";
}
