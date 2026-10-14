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
  options.myConfig.modules.pkg-config.enable = lib.mkEnableOption "pkg-config build tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.pkg-config ]; };
}
