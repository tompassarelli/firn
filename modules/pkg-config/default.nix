{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.pkg-config;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pkg-config ]; };
  options.myConfig.modules.pkg-config.enable = lib.mkEnableOption "pkg-config build tool";
}
