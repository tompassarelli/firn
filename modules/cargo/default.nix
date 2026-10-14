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
  options.myConfig.modules.cargo.enable = lib.mkEnableOption "Rust package manager";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.cargo ]; };
}
