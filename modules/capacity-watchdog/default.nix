{
  config,
  lib,
  pkgs,
  northBin,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.capacity-watchdog;
  username = config.myConfig.modules.users.username;
  inherit (cfg) rest;
  description = "capacity-watchdog: sample load, PSI, cgroup CPU and unleased processes every 30 s; log incidents and stop stray git maintenance";
  path = "PATH=${unitPath}:${
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
              Slice = "control.slice";
              Type = "simple";
              Restart = "always";
              RestartSec = "10s";
              CPUWeight = 200;
              MemoryMax = "512M";
              Environment = [
                path
              ];
              ExecStart = "${northBin}/north capacity watchdog sample";
            };
            Install.WantedBy = [ "default.target" ];
          };
        };
      };
    };
  };
}
