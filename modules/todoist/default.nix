{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.todoist;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.todoist-electron ]; };
  options.myConfig.modules.todoist.enable = lib.mkEnableOption "Todoist task manager";
}
