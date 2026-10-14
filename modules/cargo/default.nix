{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.cargo;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.cargo ]; };
  options.myConfig.modules.cargo.enable = lib.mkEnableOption "Rust package manager";
}
