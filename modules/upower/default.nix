{ config, lib, ... }:
let
  cfg = config.myConfig.modules.upower;
in
{
  options.myConfig.modules.upower.enable = lib.mkEnableOption "UPower power management";
  config = lib.mkIf cfg.enable { services.upower.enable = true; };
}
