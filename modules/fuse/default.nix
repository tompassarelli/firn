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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.fuse ]; };
  options.myConfig.modules.fuse.enable = lib.mkEnableOption "FUSE filesystem support";
}
