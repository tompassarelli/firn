{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.supply-chain-scan;
  username = config.myConfig.modules.users.username;
  description = "Daily osv-scanner pass over origin/main lockfiles; alerts through supply-alert on new malware or fixable advisories";
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${
    lib.makeBinPath [
      pkgs.osv-scanner
      pkgs.git
      pkgs.jq
      pkgs.openssh
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.bash
    ]
  }";
in
{
  options.myConfig.modules.supply-chain-scan.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.osv-scanner ];
    home-manager.users.${username} = _: {
      systemd.user = {
        services.supply-chain-scan = {
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
            ExecStart = "${northBin}/north supply-chain-scan";
          };
        };
        timers.supply-chain-scan = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "*-*-* 07:23:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
