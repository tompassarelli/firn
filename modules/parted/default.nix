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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.parted ]; };
  options.myConfig.modules.parted.enable = lib.mkEnableOption "disk partitioning tool";
}
