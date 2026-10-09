{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.skill-review-queue.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.skill-review-queue.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.skill-review-queue = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/bin:${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.gh pkgs.git ]}"
          ];
          ExecStart = "${homeDir}/.local/bin/skill-review-queue";
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
}) "Weekly skill review queue: open or update the north issue listing skill reviews older than 30 days")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
