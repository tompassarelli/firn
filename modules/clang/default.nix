{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.clang;
in
{
  options.myConfig.modules.clang.enable = lib.mkEnableOption "Clang C/C++ compiler";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.clang ]; };
}
