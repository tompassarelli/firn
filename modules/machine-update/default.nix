{ config, lib, pkgs, jobRun, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  writer = config.myConfig.modules.machine-update.writer;
  command = if writer then "--write" else "--apply";
  jobName = if writer then "machine-update" else "machine-update-apply";
in {
  options.myConfig.modules.machine-update.enable = lib.mkEnableOption "Nightly machine software update";
  options.myConfig.modules.machine-update.writer = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Land nightly security inputs; other hosts only apply the landed inputs";
  };
  config = lib.mkIf config.myConfig.modules.machine-update.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.machine-update = {
        Unit = {
          Description = "Nightly machine software update";
          OnFailure = [
            (if writer then "nexus-notify@%n.service" else "update-notify@%n.service")
          ];
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          TimeoutStartSec = "4h";
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [
              pkgs.bash
              pkgs.bun
              pkgs.coreutils
              pkgs.curl
              pkgs.git
              pkgs.gh
              pkgs.jq
              pkgs.nix
              pkgs.python3
              pkgs.zstd
              pkgs.util-linux
              pkgs.libnotify
              pkgs.systemd
            ]}"
          ];
          ExecStart = jobRun jobName "${homeDir}/.local/share/firn/bin/machine-update ${command}";
        };
      };
      systemd.user.timers.machine-update = {
        Unit = {
          Description = "Nightly machine software update";
        };
        Timer = {
          OnCalendar = "02:00";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}
