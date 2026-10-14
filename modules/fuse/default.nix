{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.fuse;
in
{
  options.myConfig.modules.fuse.enable = lib.mkEnableOption "FUSE filesystem support";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.fuse ]; };
}
