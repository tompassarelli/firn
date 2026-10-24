{ config, lib, ... }:
let
  cfg = config.myConfig.modules.upower;
in
{
  options.myConfig.modules.upower.enable = lib.mkEnableOption "UPower power management";
  config = lib.mkIf cfg.enable {
    services.upower = {
      enable = true;
      percentageLow = 20;
      percentageCritical = 12;
      percentageAction = 8;
      criticalPowerAction = "HybridSleep";
    };
  };
}
