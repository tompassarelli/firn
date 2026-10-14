{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sqlite;
in
{
  options.myConfig.modules.sqlite.enable = lib.mkEnableOption "SQLite database";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sqlite ]; };
}
