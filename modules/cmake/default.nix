{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.cmake;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.cmake ]; };
  options.myConfig.modules.cmake.enable = lib.mkEnableOption "CMake build system";
}
