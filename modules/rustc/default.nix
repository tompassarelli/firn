{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.rustc;
in
{
  options.myConfig.modules.rustc.enable = lib.mkEnableOption "Rust compiler";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.rustc ]; };
}
