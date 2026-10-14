{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.duf;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.duf ]; };
  options.myConfig.modules.duf.enable = lib.mkEnableOption "duf disk usage viewer";
}
