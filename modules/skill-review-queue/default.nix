{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.skill-review-queue;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  gh =
    if config.myConfig.modules.github-pat.enable then
      config.myConfig.modules.github-pat.gh
    else
      pkgs.gh;
  notify =
    if config.myConfig.modules.nexus-alerts.enable then
      "nexus-notify@%n.service"
    else
      "update-notify@%n.service";
  description = "Weekly skill review queue: open or update the north issue listing skill reviews older than 30 days";
in
{
  options.myConfig.modules.skill-review-queue.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.skill-review-queue = {
          Unit = {
            Description = description;
            OnFailure = [ notify ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "PATH=${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.jq
                  gh
                  pkgs.git
                ]
              }"
            ];
            ExecStart = jobRun "skill-review-queue" "${northBin}/skill-review-queue";
          };
        };
        timers.skill-review-queue = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "Mon 09:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
