{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.rustfmt;
in
{
  options.myConfig.modules.rustfmt.enable = lib.mkEnableOption "Rust formatter";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.rustfmt ]; };
}
