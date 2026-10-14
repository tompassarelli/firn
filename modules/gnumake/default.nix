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
  options.myConfig.modules.gnumake.enable = lib.mkEnableOption "GNU Make build tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gnumake ]; };
}
