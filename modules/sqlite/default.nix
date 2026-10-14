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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sqlite ]; };
  options.myConfig.modules.sqlite.enable = lib.mkEnableOption "SQLite database";
}
