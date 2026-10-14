{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.jq;
in
{
  options.myConfig.modules.jq.enable = lib.mkEnableOption "jq command-line JSON processor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.jq ]; };
}
