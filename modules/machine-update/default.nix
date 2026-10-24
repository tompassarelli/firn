{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.machine-update;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  run = jobName: mode: jobRun jobName "${homeDir}/.local/share/firn/bin/machine-update ${mode}";
in
{
  options.myConfig.modules.machine-update = {
    enable = lib.mkEnableOption "Nightly machine software update";
    writer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Land nightly security inputs; other hosts only apply the landed inputs";
    };
    apply = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.writer;
      defaultText = lib.literalExpression "!writer";
      description = "Rebuild this host from the landed inputs, after landing them when it is also the writer";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.machine-update = {
          Unit = {
            Description = "Nightly machine software update";
            OnFailure = [
              (if cfg.apply then "update-notify@%n.service" else "nexus-notify@%n.service")
            ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            TimeoutStartSec = "4h";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
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
                ]
              }"
            ];
            ExecStart =
              lib.optional cfg.writer (run "machine-update" "--write")
              ++ lib.optional cfg.apply (run "machine-update-apply" "--apply");
          };
        };
        timers.machine-update = {
          Unit.Description = "Nightly machine software update";
          Timer = {
            OnCalendar = "02:00";
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
