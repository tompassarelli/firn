{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.rust-analyzer;
in
{
  options.myConfig.modules.rust-analyzer.enable = lib.mkEnableOption "Rust language server";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.rust-analyzer ]; };
}
