{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: {
  options.myConfig.modules.laptop-runner.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.laptop-runner.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.laptop-runner = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
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
}) "laptop-runner: each minute and on wake, run jobs queued on the ledger for the laptop, one at a time")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
