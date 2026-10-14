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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.procs ]; };
  options.myConfig.modules.procs.enable = lib.mkEnableOption "procs";
}
