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
  options.myConfig.modules.slack.enable = lib.mkEnableOption "Slack messaging";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.slack ]; };
}
