{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gnumake;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gnumake ]; };
  options.myConfig.modules.gnumake.enable = lib.mkEnableOption "GNU Make build tool";
}
