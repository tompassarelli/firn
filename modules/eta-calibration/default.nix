{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.eta-calibration;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  gh =
    if config.myConfig.modules.github-pat.enable then
      config.myConfig.modules.github-pat.gh
    else
      pkgs.gh;
  description = "Weekly ETA calibration: post the last 7 days of stated ETA against measured active minutes, per category and tier, to north#255";
in
{
  options.myConfig.modules.eta-calibration.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.eta-calibration = {
          Unit = {
            Description = description;
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${
                lib.makeBinPath [
                  pkgs.coreutils
                  gh
                ]
              }"
            ];
            ExecStart = jobRun "eta-calibration" "${northBin}/north eta-calibration";
          };
        };
        timers.eta-calibration = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "Mon *-*-* 09:15:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
