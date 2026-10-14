{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.procps;
in
{
  options.myConfig.modules.procps.enable = lib.mkEnableOption "procps";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.procps ]; };
}
