{
  config,
  lib,
  pkgs,
  jobRun,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-vulnix;
  scanner = pkgs.writeShellApplication {
    name = "nexus-vulnix";
    runtimeInputs = [
      pkgs.vulnix
      pkgs.python3
      "/run/current-system/sw"
    ];
    text = "exec python3 ${./nexus-vulnix.py} \"$@\"";
  };
  notifyMask = pkgs.writeTextDir "lib/systemd/system/nexus-vulnix.service.d/10-nexus-notify.conf" "";
in
{
  options.myConfig.modules.nexus-vulnix.enable =
    lib.mkEnableOption "Weekly system vulnerability report with alerts for new high/critical CVSSv3 findings";
  config = lib.mkIf cfg.enable {
    systemd = {
      packages = [ notifyMask ];
      services.nexus-vulnix = {
        description = "Scan the system closure for new high/critical vulnerabilities";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nexus-vulnix";
          StateDirectoryMode = "0700";
          CacheDirectory = "nexus-vulnix";
          Environment = "XDG_CACHE_HOME=/var/cache/nexus-vulnix";
          UMask = "0077";
          Nice = 10;
          TimeoutStartSec = "2h";
          ExecStart = jobRun "nexus-vulnix" "${scanner}/bin/nexus-vulnix";
        };
      };
      timers.nexus-vulnix = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun 03:00";
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
      };
    };
    environment.systemPackages = [ scanner ];
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${config.myConfig.modules.users.username}' &&
            action.lookup('unit') == 'nexus-vulnix.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
  };
}
