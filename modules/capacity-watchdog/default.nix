{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.capacity-watchdog;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  inherit (cfg) rest;
  description = "capacity-watchdog: sample load, PSI, cgroup CPU and unleased processes every 30 s; log incidents and stop stray git maintenance";
  nightly = "git-maintenance-nightly: run git maintenance for ~/code/*/main one repo at a time inside a moderate capacity lease";
  path =
    north:
    "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${north}:${
      lib.makeBinPath [
        pkgs.bun
        pkgs.git
        pkgs.coreutils
        pkgs.libnotify
        pkgs.systemd
      ]
    }";
in
{
  options.myConfig.modules.capacity-watchdog = {
    enable = lib.mkEnableOption description;
    rest = {
      system = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "rest-check: system unit globs expected at rest; empty writes no rest.json";
      };
      user = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "rest-check: user unit globs expected at rest";
      };
      sockets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "rest-check: listening socket globs, PROTO ADDR:PORT UNIT";
      };
      cores = lib.mkOption {
        type = lib.types.float;
        default = builtins.fromJSON "0.02";
        description = "rest-check: default per-unit CPU budget in cores";
      };
      budgets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "rest-check: per-unit CPU budgets, UNIT CORES";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      xdg.configFile = lib.optionalAttrs (rest.system != [ ]) {
        "capacity-watchdog/rest.json".text = builtins.toJSON rest;
      };
      systemd.user = {
        services = {
          capacity-watchdog = {
            Unit.Description = description;
            Service = {
              Type = "simple";
              Restart = "always";
              RestartSec = "10s";
              CPUWeight = 200;
              MemoryMax = "512M";
              Environment = [
                (path "${homeDir}/.local/share/north/bin")
                "Malloc=1"
                "JSC_numberOfGCMarkers=1"
              ];
              ExecStart = "${homeDir}/.local/share/north/bin/capacity-watchdog sample";
            };
            Install.WantedBy = [ "default.target" ];
          };
          git-maintenance-nightly = {
            Unit = {
              Description = nightly;
              OnFailure = [ "update-notify@%n.service" ];
            };
            Service = {
              Type = "oneshot";
              Nice = 10;
              TimeoutStartSec = "4h";
              Environment = [ (path northBin) ];
              ExecStart = jobRun "git-maintenance-nightly" "${northBin}/git-maintenance-nightly";
            };
          };
        };
        timers.git-maintenance-nightly = {
          Unit.Description = nightly;
          Timer = {
            OnCalendar = "*-*-* 03:17:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
