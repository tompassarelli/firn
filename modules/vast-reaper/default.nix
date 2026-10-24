{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.vast-reaper;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "vast.ai reaper: every 5 minutes destroy vast-job instances past their deadline or without a live supervisor, and tear down the runner VM at the credit floor";
in
{
  options.myConfig.modules.vast-reaper.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.vast-reaper = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.bun
                  pkgs.coreutils
                  pkgs.sops
                  pkgs.gh
                  pkgs.libnotify
                ]
              }"
            ];
            ExecStart = jobRun "vast-reaper" "${northBin}/vast-reaper";
          };
        };
        timers.vast-reaper = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "2min";
            OnUnitActiveSec = "5min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
