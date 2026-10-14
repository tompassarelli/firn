{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sqlcmd;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sqlcmd ]; };
  options.myConfig.modules.sqlcmd.enable = lib.mkEnableOption "sqlcmd for Microsoft SQL Server";
}
