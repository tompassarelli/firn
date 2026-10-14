{ config, lib, ... }:
let
  cfg = config.myConfig.modules.thermal-management;
in
{
  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "amd_pstate=active" ];
    services.auto-cpufreq = {
      enable = true;
      settings = {
        battery = {
          energy_performance_preference = "power";
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          energy_performance_preference = "balance_performance";
          governor = "performance";
          turbo = "never";
        };
      };
    };
  };
  options.myConfig.modules.thermal-management.enable =
    lib.mkEnableOption "CPU thermal management for sustained builds";
}
