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
        NTFY_AUTH_ACCESS='phone:urgent:ro,phone:normal:ro,nexus:urgent:wo,nexus:normal:wo,nexus:socrates-test:rw'
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
          name=''${unit%.service}
          result=$(systemctl show "$unit" -p Result --value)
          status=$(systemctl show "$unit" -p ExecMainStatus --value)
          case "$result" in
            exit-code) reason="it exited with error code $status" ;;
            timeout) reason='it took too long and was stopped' ;;
            signal) reason='it was killed by a signal' ;;
            core-dump) reason='it crashed' ;;
            oom-kill) reason='it ran out of memory' ;;
            start-limit-hit) reason='it kept failing and systemd stopped restarting it' ;;
            *) reason="systemd reports: ''${result:-unknown}" ;;
          esac
          title="Nexus: $name failed"
          case "$name" in nexus-selftest-*) title="Nexus self-test (no action needed): $name failed" ;; esac
          last=$(journalctl -u "$unit" -n 1 --no-pager -o cat | cut -c1-200)
          lines=$(journalctl -u "$unit" -n 10 --no-pager -o cat | tail -c 3000)
          nexus-alert urgent "$(printf '%s failed because %s.\nLast log line: %s\n\n%s' "$name" "$reason" "$last" "$lines")" "$title"
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
      usage() { echo 'usage: nexus-alert urgent|normal|socrates-test TEXT [TITLE] [CLICK]' >&2; exit 2; }
      [ $# -ge 2 ] && [ $# -le 4 ] || usage
      case "$1" in urgent) prio=5 ;; normal|socrates-test) prio=3 ;; *) usage ;; esac
      title=''${3:-Nexus}
      click=''${4:-}
      token=$(cat ${config.sops.secrets.ntfy-publisher-token.path})
      curl -fsS -o /dev/null -H @<(printf 'Authorization: Bearer %s\nPriority: %s\nTitle: %s\n' "$token" "$prio" "$title"; [ -z "$click" ] || printf 'Click: %s\n' "$click") \
        --data-binary "$2" "${baseUrl}/$1"
    '';
  }))) (builtins.getAttr "ntfy-auth.env" config.sops.templates))) config.sops.placeholder)) "${flakeRoot}/secrets/nexus/ntfy.yaml")) "http://${listen}")) "10.77.0.1:${builtins.toString port}")) 2586)) config.myConfig.modules.users.username)
