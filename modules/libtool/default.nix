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
  options.myConfig.modules.libtool.enable = lib.mkEnableOption "GNU Libtool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.libtool ]; };
}
