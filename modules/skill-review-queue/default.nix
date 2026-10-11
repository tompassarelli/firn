{ config, lib, pkgs, jobRun, ... }:

((homeDir: ((username: ((gh: ((notify: ((description: {
  options.myConfig.modules.skill-review-queue.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.skill-review-queue.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.skill-review-queue = {
        Unit = {
          Description = description;
          OnFailure = [ notify ];
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.jq gh pkgs.git ]}"
          ];
          ExecStart = jobRun "skill-review-queue" "${homeDir}/.local/share/north/bin/skill-review-queue";
        };
      };
      systemd.user.timers.skill-review-queue = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = "Mon 09:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "Weekly skill review queue: open or update the north issue listing skill reviews older than 30 days")) (if config.myConfig.modules.nexus-alerts.enable then "nexus-notify@%n.service" else "update-notify@%n.service"))) (if config.myConfig.modules.github-pat.enable then config.myConfig.modules.github-pat.gh else pkgs.gh))) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
