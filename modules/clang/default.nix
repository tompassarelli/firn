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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.clang ]; };
  options.myConfig.modules.clang.enable = lib.mkEnableOption "Clang C/C++ compiler";
}
