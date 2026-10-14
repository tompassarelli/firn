{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.musl;
in
{
  options.myConfig.modules.musl.enable = lib.mkEnableOption "musl C compiler toolchain";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.musl.dev ]; };
}
