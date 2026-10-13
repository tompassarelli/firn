{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.modules.laptop-window;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
in {
  options.myConfig.modules.laptop-window.enable = lib.mkEnableOption "laptop-window: every minute run laptop tick, opening the laptop at the window's open time, draining it at its close and settling drained state";
  options.myConfig.modules.laptop-window.timeZone = lib.mkOption {
    type = lib.types.str;
    default = "UTC";
    description = "time zone the window and laptop until HH:MM are read in";
  };
  options.myConfig.modules.laptop-window.open = lib.mkOption {
    type = lib.types.str;
    default = "23:00";
    description = "local time the window makes the laptop available";
  };
  options.myConfig.modules.laptop-window.close = lib.mkOption {
    type = lib.types.str;
    default = "10:00";
    description = "local time the window drains the laptop";
  };
  config = lib.mkIf cfg.enable {
    environment.etc."placement/laptop-window.json".text = builtins.toJSON {
      tz = cfg.timeZone;
      open = cfg.open;
      close = cfg.close;
    };
    systemd.services.laptop-window = {
      description = "laptop tick: apply the laptop availability window and settle a finished drain";
      path = [
        pkgs.python3
        pkgs.coreutils
        pkgs.gitleaks
        "${homeDir}/.local/share/north"
        "/run/current-system/sw"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        TimeoutStartSec = "50s";
        ExecStart = "${homeDir}/.local/share/north/bin/laptop tick";
      };
    };
    systemd.timers.laptop-window = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
        AccuracySec = "1s";
      };
    };
  };
}
