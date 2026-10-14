{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.clippy;
in
{
  options.myConfig.modules.clippy.enable = lib.mkEnableOption "Rust linter";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.clippy ]; };
}
