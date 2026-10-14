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
  options.myConfig.modules.sqlcmd.enable = lib.mkEnableOption "sqlcmd for Microsoft SQL Server";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sqlcmd ]; };
}
