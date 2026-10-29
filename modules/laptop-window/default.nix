{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.laptop-window;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.laptop-window = {
    enable = lib.mkEnableOption "laptop-window: every minute run laptop tick, opening the laptop at the window's open time, draining it at its close and settling drained state";
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "time zone the window and laptop until HH:MM are read in";
    };
    open = lib.mkOption {
      type = lib.types.str;
      default = "23:00";
      description = "local time the window makes the laptop available";
    };
    close = lib.mkOption {
      type = lib.types.str;
      default = "10:00";
      description = "local time the window drains the laptop";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc."placement/laptop-window.json".text = builtins.toJSON {
      tz = cfg.timeZone;
      inherit (cfg) open;
      inherit (cfg) close;
    };
    systemd = {
      services.laptop-window = {
        description = "laptop tick: apply the laptop availability window and settle a finished drain";
        unitConfig.ConditionFileIsExecutable = "${northBin}/north";
        path = [
          pkgs.python3
          pkgs.coreutils
          pkgs.gitleaks
          (dirOf northBin)
          "/run/current-system/sw"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          TimeoutStartSec = "50s";
          ExecStart = "${northBin}/north laptop tick";
        };
      };
      timers.laptop-window = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          AccuracySec = "1s";
        };
      };
    };
  };
}
