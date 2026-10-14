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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.jq ]; };
  options.myConfig.modules.jq.enable = lib.mkEnableOption "jq command-line JSON processor";
}
