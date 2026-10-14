{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gnumeric;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gnumeric ]; };
  options.myConfig.modules.gnumeric.enable =
    lib.mkEnableOption "Gnumeric lightweight spreadsheet (xlsx/ods/csv viewer)";
}
