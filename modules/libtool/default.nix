{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.libtool;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libtool ]; };
  options.myConfig.modules.libtool.enable = lib.mkEnableOption "GNU Libtool";
}
