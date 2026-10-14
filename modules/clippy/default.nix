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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.clippy ]; };
  options.myConfig.modules.clippy.enable = lib.mkEnableOption "Rust linter";
}
