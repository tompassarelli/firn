{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.procs;
in
{
  options.myConfig.modules.procs.enable = lib.mkEnableOption "procs";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.procs ]; };
}
