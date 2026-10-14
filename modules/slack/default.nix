{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.slack;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.slack ]; };
  options.myConfig.modules.slack.enable = lib.mkEnableOption "Slack messaging";
}
