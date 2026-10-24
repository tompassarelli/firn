{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-laptop-ntfy;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  port = 2588;
  serve = "${homeDir}/.local/share/north/bin/laptop-ntfy";
  notify = "${northBin}/laptop-ntfy";
  toolPath = tool: [
    pkgs.python3
    pkgs.coreutils
    pkgs.gitleaks
    (dirOf (dirOf tool))
    "/run/current-system/sw"
  ];
  env = {
    LAPTOP_NTFY_URL = "http://10.77.0.1:2586";
    LAPTOP_NTFY_TOPIC = "socrates-laptop";
    LAPTOP_NTFY_TOKEN_FILE = config.sops.secrets.ntfy-publisher-token.path;
    LAPTOP_NTFY_ACTION_TOKEN_FILE = config.sops.secrets.laptop-action-token.path;
    LAPTOP_NTFY_ACTION_URL = "http://10.77.0.1:${builtins.toString port}";
    LAPTOP_NTFY_LISTEN = "10.77.0.1:${builtins.toString port}";
  };
in
{
  options.myConfig.modules.nexus-laptop-ntfy = {
    enable = lib.mkEnableOption "nexus-laptop-ntfy: ntfy topic socrates-laptop with a daily window reminder carrying Open and Close buttons, and the authenticated endpoint the buttons call";
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file holding laptop-action-token, the bearer token the ntfy buttons send";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.laptop-action-token = {
      inherit (cfg) sopsFile;
      owner = username;
      mode = "0400";
    };
    networking.firewall.interfaces.wg-nexus.allowedTCPPorts = [ port ];
    systemd = {
      services = {
        nexus-laptop-ntfy = {
          description = "Endpoint for the laptop Open and Close buttons in ntfy";
          wantedBy = [ "multi-user.target" ];
          after = [ "wireguard-wg-nexus.service" ];
          path = toolPath serve;
          environment = env;
          serviceConfig = {
            User = username;
            Restart = "always";
            RestartSec = 5;
            TimeoutStartSec = "15min";
            ExecStartPre = "${pkgs.coreutils}/bin/timeout 800 ${pkgs.bash}/bin/bash -c 'until [ -x ${serve} ]; do sleep 5; done'";
            ExecStart = "${serve} serve";
          };
        };
        nexus-laptop-ntfy-notify = {
          description = "Publish the daily laptop window reminder to ntfy";
          unitConfig.ConditionPathIsExecutable = notify;
          path = toolPath notify;
          environment = env;
          serviceConfig = {
            Type = "oneshot";
            User = username;
            TimeoutStartSec = "50s";
            ExecStart = "${notify} notify";
          };
        };
      };
      timers.nexus-laptop-ntfy-notify = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          AccuracySec = "1s";
        };
      };
    };
  };
}
