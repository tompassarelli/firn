{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.hyperfine;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.hyperfine ]; };
  options.myConfig.modules.hyperfine.enable = lib.mkEnableOption "hyperfine command benchmarking";
}
