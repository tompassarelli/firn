{ config, lib, pkgs, ... }:

let
  watchdog = pkgs.writeShellApplication {
    name = "north-watchdog";
    runtimeInputs = with pkgs; [ coreutils gawk netcat-openbsd systemd ];
    text = builtins.readFile ./north-watchdog;
  };
  watchdog-status = pkgs.writeShellApplication {
    name = "north-watchdog-status";
    runtimeInputs = with pkgs; [ coreutils gawk ];
    text = builtins.readFile ./north-watchdog-status;
  };
in
{
  options.myConfig.modules.north-watchdog.enable = lib.mkEnableOption "North active-slot coordination watchdog";
  config = lib.mkIf config.myConfig.modules.north-watchdog.enable {
    environment.systemPackages = [ watchdog watchdog-status ];
    systemd.services.north-watchdog = {
      description = "Probe and recover the active North coordination slot";
      after = [ "north-coord-blue-green.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        StateDirectory = "north-watchdog";
        StateDirectoryMode = "0700";
        ExecStart = "${watchdog}/bin/north-watchdog";
      };
    };
    systemd.timers.north-watchdog = {
      description = "Probe the active North coordination slot every 60 seconds";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "60s";
        OnUnitActiveSec = "60s";
        Unit = "north-watchdog.service";
      };
    };
  };
}
