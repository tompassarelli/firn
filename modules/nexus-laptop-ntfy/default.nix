{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.modules.nexus-laptop-ntfy;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  port = 2588;
  base = "${homeDir}/.local/share/north/bin/laptop-ntfy";
  toolPath = [
    pkgs.python3
    pkgs.coreutils
    pkgs.gitleaks
    "${homeDir}/.local/share/north"
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
in {
  options.myConfig.modules.nexus-laptop-ntfy.enable = lib.mkEnableOption "nexus-laptop-ntfy: ntfy topic socrates-laptop with Open and Close buttons on every laptop state change, a daily window reminder and the authenticated endpoint the buttons call";
  options.myConfig.modules.nexus-laptop-ntfy.sopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file holding laptop-action-token, the bearer token the ntfy buttons send";
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.laptop-action-token = {
      sopsFile = cfg.sopsFile;
      owner = username;
      mode = "0400";
    };
    networking.firewall.interfaces.wg-nexus.allowedTCPPorts = [ port ];
    systemd.services.nexus-laptop-ntfy = {
      description = "Endpoint for the laptop Open and Close buttons in ntfy";
      wantedBy = [ "multi-user.target" ];
      after = [ "wireguard-wg-nexus.service" ];
      path = toolPath;
      environment = env;
      serviceConfig = {
        User = username;
        Restart = "always";
        RestartSec = 5;
        ExecStart = "${base} serve";
      };
    };
    systemd.services.nexus-laptop-ntfy-notify = {
      description = "Publish the laptop state to ntfy when it changed";
      path = toolPath;
      environment = env;
      serviceConfig = {
        Type = "oneshot";
        User = username;
        TimeoutStartSec = "50s";
        ExecStart = "${base} notify";
      };
    };
    systemd.timers.nexus-laptop-ntfy-notify = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
        AccuracySec = "1s";
      };
    };
  };
}
