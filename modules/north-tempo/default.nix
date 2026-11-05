{
  config,
  lib,
  jobRun,
  northBin,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.north-tempo;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "Hourly landing tempo: record north's lanes landed, queued->main and first commit->main p50 and p90 over the last hour and day into the ledger, then fail when a lander-held learning loop is stale";
in
{
  options.myConfig.modules.north-tempo.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.north-tempo = {
          Unit = {
            Description = description;
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${homeDir}/.local/bin:${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.git
                  pkgs.openssh
                ]
              }"
            ];
            ExecStart = jobRun "north-tempo" "${northBin}/north tempo --record";
            ExecStartPost = jobRun "north-loops-lander" "${northBin}/north loops check --role lander";
          };
        };
        timers.north-tempo = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "hourly";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
