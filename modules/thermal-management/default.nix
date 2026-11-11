{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.thermal-management;
  chargerProfile = pkgs.writeShellApplication {
    name = "charger-profile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      ${builtins.readFile ../upower/power-readings.sh}
      ${builtins.readFile ./profile.sh}
      read -r now _ </proc/uptime
      charger_profile_run /sys/class/power_supply "$RUNTIME_DIRECTORY" /sys/firmware/acpi/platform_profile /run/user "''${now%.*}"
    '';
  };
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
          turbo = "always";
        };
      };
    };
    services.udev.extraRules = ''
      ACTION=="change", SUBSYSTEM=="power_supply", RUN+="${config.systemd.package}/bin/systemctl start --no-block charger-profile.service"
    '';
    systemd = {
      services.charger-profile = {
        description = "Choose the platform profile on the charger from whether the battery is charging";
        unitConfig.ConditionPathExists = "/sys/firmware/acpi/platform_profile";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe chargerProfile;
          RuntimeDirectory = "charger-profile";
          RuntimeDirectoryPreserve = true;
          LogLevelMax = "notice";
        };
      };
      timers.charger-profile = {
        description = "Read the charger, the battery and the gaming hold every 20 s";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "20s";
          OnUnitActiveSec = "20s";
          AccuracySec = "1s";
        };
      };
    };
  };
}
