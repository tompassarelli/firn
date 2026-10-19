{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.nexus-alerts;
  username = config.myConfig.modules.users.username;
  port = 2586;
  listen = "10.77.0.1:${builtins.toString port}";
  baseUrl = "http://${listen}";
  inherit (cfg) sopsFile;
  ph = config.sops.placeholder;
  envTemplate = config.sops.templates."ntfy-auth.env";
  nexusAlert = pkgs.writeShellApplication {
    name = "nexus-alert";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      : "''${NEXUS_ALERT_NTFY_URL:=${baseUrl}}"
      : "''${NEXUS_ALERT_NTFY_TOKEN_FILE:=${config.sops.secrets.ntfy-publisher-token.path}}"
    ''
    + builtins.readFile ./nexus-alert.sh;
  };
  logBody = ''
    name=''${unit%.service}
    result=$(systemctl $scope show "$unit" -p Result --value)
    status=$(systemctl $scope show "$unit" -p ExecMainStatus --value)
    last=$(journalctl $scope -u "$unit" -n 1 --no-pager -o cat | cut -c1-200)
    echo "$name failed: result ''${result:-unknown}, status ''${status:-unknown}; last log line: $last"
  '';
  userLog = pkgs.writeShellScript "nexus-notify-user" ''
    unit=$1
    scope=--user
    ${logBody}
  '';
in
{
  options.myConfig.modules.nexus-alerts = {
    enable = lib.mkEnableOption "nexus push alerts through ntfy (urgent at priority 5, normal at priority 2) and the nexus-alert CLI";
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops file holding the ntfy publisher and phone tokens and hashes";
    };
  };
  config = lib.mkIf cfg.enable {
    sops = {
      secrets = {
        ntfy-publisher-token = {
          inherit sopsFile;
          owner = username;
          mode = "0400";
        };
        ntfy-phone-hash.sopsFile = sopsFile;
        ntfy-phone-token.sopsFile = sopsFile;
        ntfy-publisher-hash.sopsFile = sopsFile;
      };
      templates."ntfy-auth.env" = {
        restartUnits = [ "ntfy-sh.service" ];
        content = ''
          NTFY_AUTH_USERS='phone:${ph.ntfy-phone-hash}:user,nexus:${ph.ntfy-publisher-hash}:user'
          NTFY_AUTH_ACCESS='phone:urgent:ro,phone:normal:ro,nexus:urgent:wo,nexus:normal:wo,nexus:socrates-test:rw,phone:socrates-laptop:ro,nexus:socrates-laptop:wo'
          NTFY_AUTH_TOKENS='phone:${ph.ntfy-phone-token}:phone,nexus:${ph.ntfy-publisher-token}:publisher'

        '';
      };
    };
    services.ntfy-sh = {
      enable = true;
      environmentFile = envTemplate.path;
      settings = {
        base-url = baseUrl;
        listen-http = listen;
        upstream-base-url = "https://ntfy.sh";
        auth-default-access = "deny-all";
        enable-login = true;
      };
    };
    networking.firewall.interfaces.wg-nexus.allowedTCPPorts = [ port ];
    environment.systemPackages = [ nexusAlert ];
    systemd.services = {
      ntfy-sh.after = [ "wireguard-wg-nexus.service" ];
      "nexus-notify@" = {
        description = "Log a failed unit %i to the journal";
        path = [
          pkgs.systemd
          pkgs.coreutils
        ];
        scriptArgs = "%i";
        script = ''
          unit=$1
          scope=
          ${logBody}
        '';
        serviceConfig.Type = "oneshot";
      };
    };
    home-manager.users.${username} = _: {
      systemd.user.services."nexus-notify@" = {
        Unit.Description = "Log a failed user unit %i to the journal";
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${
              lib.makeBinPath [
                pkgs.systemd
                pkgs.coreutils
              ]
            }"
          ];
          ExecStart = "${userLog} %i";
        };
      };
    };
  };
}
