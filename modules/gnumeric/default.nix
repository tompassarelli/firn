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
  options.myConfig.modules.gnumeric.enable =
    lib.mkEnableOption "Gnumeric lightweight spreadsheet (xlsx/ods/csv viewer)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gnumeric ]; };
}
