{ config, lib, pkgs, ... }:

((cfg: ((homeDir: ((username: ((notify: ((description: {
  options.myConfig.modules.laptop-runner.enable = lib.mkEnableOption description;
  options.myConfig.modules.laptop-runner.placement = lib.mkOption {
    type = lib.types.str;
    default = "laptop";
    description = "ledger queue placement this host's runner takes jobs for";
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.laptop-runner = {
        Unit = {
          Description = description;
          OnFailure = [ notify ];
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${homeDir}/.local/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.jq
              pkgs.util-linux
              pkgs.openssh
              pkgs.python3
            ]}:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin"
            "LAPTOP_RUNNER_PLACEMENT=${cfg.placement}"
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/laptop-runner";
        };
      };
      systemd.user.timers.laptop-runner = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = "minutely";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "laptop-runner: each minute and on wake, run jobs queued on the ledger for this host's placement, one at a time")) (if config.myConfig.modules.nexus-alerts.enable then "nexus-notify@%n.service" else "update-notify@%n.service"))) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)) config.myConfig.modules.laptop-runner)
