{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.parted;
in
{
  options.myConfig.modules.parted.enable = lib.mkEnableOption "disk partitioning tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.parted ]; };
}
