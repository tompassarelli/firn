{ config, lib, ... }:
let
  cfg = config.myConfig.modules.thermal-management;
in
{
  options.myConfig.modules.thermal-management.enable =
    lib.mkEnableOption "CPU thermal management for sustained builds";
  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "amd_pstate=active" ];
    services.auto-cpufreq = {
      enable = true;
      settings = {
        battery = {
          energy_performance_preference = "power";
          governor = "powersave";
          platform_profile = "balanced";
          turbo = "never";
        };
        charger = {
          energy_performance_preference = "performance";
          governor = "performance";
          platform_profile = "performance";
          turbo = "always";
        };
      };
    };
  };
}
