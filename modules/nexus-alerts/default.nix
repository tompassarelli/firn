{ config, lib, pkgs, flakeRoot, ... }:

((username: ((port: ((listen: ((baseUrl: ((sopsFile: ((ph: ((envTemplate: ((nexusAlert: ((onFailureDropin: ((notifyResetDropin: {
  options.myConfig.modules.nexus-alerts.enable = lib.mkEnableOption "nexus push alerts: ntfy on wg-nexus, nexus-alert CLI, OnFailure notify for every service";
  config = lib.mkIf config.myConfig.modules.nexus-alerts.enable {
    sops.secrets.ntfy-publisher-token = {
      sopsFile = sopsFile;
      owner = username;
      mode = "0400";
    };
    sops.secrets.ntfy-phone-hash.sopsFile = sopsFile;
    sops.secrets.ntfy-phone-token.sopsFile = sopsFile;
    sops.secrets.ntfy-publisher-hash.sopsFile = sopsFile;
    sops.templates."ntfy-auth.env" = {
      restartUnits = [ "ntfy-sh.service" ];
      content = ''
        NTFY_AUTH_USERS='phone:${ph.ntfy-phone-hash}:user,nexus:${ph.ntfy-publisher-hash}:user'
        NTFY_AUTH_ACCESS='phone:urgent:ro,phone:normal:ro,nexus:urgent:wo,nexus:normal:wo'
        NTFY_AUTH_TOKENS='phone:${ph.ntfy-phone-token}:phone,nexus:${ph.ntfy-publisher-token}:publisher'

      '';
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
    systemd.packages = [ onFailureDropin notifyResetDropin ];
    systemd.services = {
      "ntfy-sh" = {
        after = [ "wireguard-wg-nexus.service" ];
      };
      "nexus-notify@" = {
        description = "Push an urgent nexus alert for failed unit %i";
        path = [ pkgs.systemd pkgs.coreutils nexusAlert ];
        scriptArgs = "%i";
        script = ''
          unit=$1
          lines=$(journalctl -u "$unit" -n 10 --no-pager -o cat | tail -c 3500)
          nexus-alert urgent "$(printf 'nexus: %s failed\n%s' "$unit" "$lines")"
        '';
        serviceConfig = {
          Type = "oneshot";
        };
      };
      "nexus-selftest-fail" = {
        description = "Deliberately failing unit for the nexus alert self-test";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/false";
        };
      };
    };
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            action.lookup('unit') == 'nexus-selftest-fail.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
  };
}) (pkgs.writeTextDir "lib/systemd/system/nexus-notify@.service.d/90-no-onfailure.conf" ''
    [Unit]
    OnFailure=

  ''))) (pkgs.writeTextDir "lib/systemd/system/service.d/10-nexus-notify.conf" ''
    [Unit]
    OnFailure=nexus-notify@%n.service

  ''))) (pkgs.writeShellApplication {
    name = "nexus-alert";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      usage() { echo 'usage: nexus-alert urgent|normal TEXT' >&2; exit 2; }
      [ $# -eq 2 ] || usage
      case "$1" in urgent) prio=5 ;; normal) prio=3 ;; *) usage ;; esac
      token=$(cat ${config.sops.secrets.ntfy-publisher-token.path})
      curl -fsS -o /dev/null -H @<(printf 'Authorization: Bearer %s\nPriority: %s\n' "$token" "$prio") \
        --data-binary "$2" "${baseUrl}/$1"
    '';
  }))) (builtins.getAttr "ntfy-auth.env" config.sops.templates))) config.sops.placeholder)) "${flakeRoot}/secrets/nexus/ntfy.yaml")) "http://${listen}")) "10.77.0.1:${builtins.toString port}")) 2586)) config.myConfig.modules.users.username)
