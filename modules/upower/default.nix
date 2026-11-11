{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.upower;
  lowBattery = pkgs.writeShellApplication {
    name = "low-battery-poweroff";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      config.systemd.package
    ];
    text = ''
      ${builtins.readFile ./low-battery.sh}
      low_battery_run /sys/class/power_supply "$RUNTIME_DIRECTORY"
    '';
  };
in
{
  options.myConfig.modules.upower.enable = lib.mkEnableOption "UPower power management";
  config = lib.mkIf cfg.enable {
    services = {
      upower = {
        enable = true;
        percentageLow = 20;
        percentageCritical = 12;
        percentageAction = 2;
        criticalPowerAction = "PowerOff";
      };
      udev.extraRules = ''
        ACTION=="change", SUBSYSTEM=="power_supply", RUN+="${config.systemd.package}/bin/systemctl start --no-block low-battery-poweroff.service"
      '';
    };
    systemd = {
      services.upower.restartTriggers = [ config.environment.etc."UPower/UPower.conf".source ];
      services.low-battery-poweroff = {
        description = "Power off on a low battery with no charger connected, and record power state changes";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe lowBattery;
          RuntimeDirectory = "low-battery-poweroff";
          RuntimeDirectoryPreserve = true;
          LogLevelMax = "notice";
        };
      };
      timers.low-battery-poweroff = {
        description = "Read the charger and the battery every 20 s";
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
