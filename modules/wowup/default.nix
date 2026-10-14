{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wowup;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.wowup-cf ]; };
  options.myConfig.modules.wowup.enable = lib.mkEnableOption "WowUp-CF addon manager";
}
