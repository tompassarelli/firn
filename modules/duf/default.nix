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
  options.myConfig.modules.duf.enable = lib.mkEnableOption "duf disk usage viewer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.duf ]; };
}
