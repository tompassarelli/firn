{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.freetds;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.freetds ]; };
  options.myConfig.modules.freetds.enable =
    lib.mkEnableOption "FreeTDS (TDS protocol library for MSSQL)";
}
