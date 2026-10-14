{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.unzip;
in
{
  options.myConfig.modules.unzip.enable = lib.mkEnableOption "unzip archive tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unzip ]; };
}
