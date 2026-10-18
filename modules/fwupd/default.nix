{
  config,
  lib,
  ...
}:
let
  cfg = config.myConfig.modules.fwupd;
in
{
  options.myConfig.modules.fwupd.enable = lib.mkEnableOption "fwupd firmware updater";
  config = lib.mkIf cfg.enable { services.fwupd.enable = true; };
}
