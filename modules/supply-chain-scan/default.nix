{ config, lib, pkgs, ... }:

((homeDir: ((username: ((description: ((path: {
  options.myConfig.modules.supply-chain-scan.enable = lib.mkEnableOption description;
  config = lib.mkIf config.myConfig.modules.supply-chain-scan.enable {
    environment.systemPackages = [ pkgs.osv-scanner ];
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.supply-chain-scan = {
        Unit = {
          Description = description;
          After = [ "network-online.target" ];
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "oneshot";
          Nice = 10;
          TimeoutStartSec = "10min";
          Environment = [ path ];
          ExecStart = "${homeDir}/.local/share/north/bin/supply-chain-scan";
        };
      };
      systemd.user.timers.supply-chain-scan = {
        Unit = {
          Description = description;
        };
        Timer = {
          OnCalendar = "*-*-* 07:23:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [
    pkgs.osv-scanner
    pkgs.git
    pkgs.jq
    pkgs.openssh
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.bash
  ]}")) "Daily osv-scanner pass over origin/main lockfiles; alerts through supply-alert on new malware or fixable advisories")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
