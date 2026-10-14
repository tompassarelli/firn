{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.fwupd;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.fwupd ]; };
  options.myConfig.modules.fwupd.enable = lib.mkEnableOption "fwupd firmware updater";
}
