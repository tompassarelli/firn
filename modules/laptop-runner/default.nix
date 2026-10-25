{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.laptop-runner;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  notify =
    if config.myConfig.modules.nexus-alerts.enable then
      "nexus-notify@%n.service"
    else
      "update-notify@%n.service";
  description = "laptop-runner: each minute and on wake, run jobs queued on the ledger for this host's placement, one at a time";
in
{
  options.myConfig.modules.laptop-runner = {
    enable = lib.mkEnableOption description;
    placement = lib.mkOption {
      type = lib.types.str;
      default = "laptop";
      description = "ledger queue placement this host's runner takes jobs for";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.laptop-auto = lib.mkIf (cfg.placement == "laptop") {
          Unit = {
            Description = "Observe laptop gaming and seat activity for placement";
            ConditionFileIsExecutable = "${northBin}/laptop-auto";
          };
          Service = {
            Type = "oneshot";
            Slice = "control.slice";
            ExecStart = "${northBin}/laptop-auto";
            TimeoutStartSec = "55s";
            Environment = "PATH=${
              lib.makeBinPath [
                pkgs.libnotify
                pkgs.python3
                pkgs.systemd
                pkgs.openssh
              ]
            }:${northBin}:/run/current-system/sw/bin";
          };
        };
        timers.laptop-auto = lib.mkIf (cfg.placement == "laptop") {
          Timer = {
            OnBootSec = "1min";
            OnUnitActiveSec = "30s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
        services.laptop-runner = {
          Unit = {
            Description = description;
            OnFailure = [ notify ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.jq
                  pkgs.util-linux
                  pkgs.openssh
                  pkgs.python3
                  pkgs.git
                  pkgs.bun
                ]
              }:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin"
              "LAPTOP_RUNNER_PLACEMENT=${cfg.placement}"
            ];
            ExecStart = "${northBin}/laptop-runner";
          };
        };
        timers.laptop-runner = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "minutely";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
