{ config, lib, pkgs, ... }:

((username: ((port: ((listen: ((baseUrl: ((sopsFile: ((ph: ((envTemplate: ((nexusAlert: ((notifyBody: ((userNotify: ((onFailureDropin: ((notifyResetDropin: {
  options.myConfig.modules.nexus-alerts.enable = lib.mkEnableOption "nexus push alerts: Matrix with ntfy fallback, nexus-alert CLI, OnFailure notify for every service";
  options.myConfig.modules.nexus-alerts.sopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file holding the ntfy publisher and phone tokens and hashes";
  };
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
          scope=
          ${notifyBody}
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
    home-manager.users.${username} = ({ ... }: {
      systemd.user.services."nexus-notify@" = {
        Unit = {
          Description = "Push an urgent nexus alert for failed user unit %i";
        };
        Service = {
          Type = "oneshot";
          Environment = [
            "PATH=${lib.makeBinPath [ pkgs.systemd pkgs.coreutils nexusAlert ]}"
          ];
          ExecStart = "${userNotify} %i";
        };
      };
    });
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

  ''))) (pkgs.writeShellScript "nexus-notify-user" ''
    unit=$1
    scope=--user
    ${notifyBody}
  ''))) ''
    name=''${unit%.service}
    result=$(systemctl $scope show "$unit" -p Result --value)
    status=$(systemctl $scope show "$unit" -p ExecMainStatus --value)
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
    last=$(journalctl $scope -u "$unit" -n 1 --no-pager -o cat | cut -c1-200)
    lines=$(journalctl $scope -u "$unit" -n 10 --no-pager -o cat | tail -c 3000)
    nexus-alert urgent "$(printf '%s failed because %s.\nLast log line: %s\n\n%s' "$name" "$reason" "$last" "$lines")" "$title"
  '')) (pkgs.writeShellApplication {
    name = "nexus-alert";
    runtimeInputs = [ pkgs.curl pkgs.coreutils pkgs.jq ];
    text = ''
      usage() { echo 'usage: nexus-alert urgent|normal|socrates-test TEXT [TITLE] [CLICK]' >&2; exit 2; }
      [ $# -ge 2 ] && [ $# -le 4 ] || usage
      case "$1" in urgent) prio=5 ;; normal|socrates-test) prio=3 ;; *) usage ;; esac
      title=''${3:-Nexus}
      click=''${4:-}
      matrix_url=''${NEXUS_ALERT_MATRIX_URL:-http://10.77.0.1:6167}
      matrix_token_file=''${NEXUS_ALERT_MATRIX_TOKEN_FILE:-/run/secrets/socrates-chat-as-token}
      matrix_server=${lib.escapeShellArg config.myConfig.modules.nexus-matrix.serverName}
      matrix_tom=${lib.escapeShellArg config.myConfig.modules.socrates-chat.tomUserId}
      matrix_room=''${NEXUS_ALERT_MATRIX_ROOM_ALIAS:-#socrates-alerts:$matrix_server}
      ntfy_url=''${NEXUS_ALERT_NTFY_URL:-${baseUrl}}
      ntfy_token_file=''${NEXUS_ALERT_NTFY_TOKEN_FILE:-${config.sops.secrets.ntfy-publisher-token.path}}
      matrix_request() {
        local remaining response status
        remaining=$(jq -nr --argjson deadline "$deadline" --argjson now "$EPOCHREALTIME" '$deadline - $now | select(. > 0)') || return 1
        [ -n "$remaining" ] || return 1
        response=$(printf 'Authorization: Bearer %s\n' "$matrix_token" | curl -s --max-time "$remaining" -H @- -w $'\n%{http_code}' "$@") || return 1
        status=''${response##*$'\n'}
        [[ $status == 2[0-9][0-9] ]] || return 1
        printf '%s' "''${response%$'\n'*}"
      }
      matrix_send() {
        local matrix_token deadline alias sender room payload response
        deadline=$(jq -nr --argjson now "$EPOCHREALTIME" '$now + 5') || return 1
        matrix_token=$(cat "$matrix_token_file") || return 1
        [ -n "$matrix_token" ] || return 1
        alias=$(jq -nr --arg value "$matrix_room" '$value | @uri') || return 1
        sender=$(jq -nr --arg value "@agent-alerts:$matrix_server" '$value | @uri') || return 1
        response=$(matrix_request "$matrix_url/_matrix/client/v3/directory/room/$alias?user_id=$sender") || return 1
        room=$(jq -er '.room_id | select(type == "string" and startswith("!")) | @uri' <<<"$response") || return 1
        payload=$(jq -n --arg topic "$1" --arg text "$2" --arg title "$title" --arg click "$click" --arg tom "$matrix_tom" '{msgtype: "m.text", body: ((if $topic == "urgent" then "Tom (" + $tom + "): " else "" end) + $title + "\n" + $text + (if $click == "" then "" else "\n" + $click end)), "m.mentions": {user_ids: (if $topic == "urgent" then [$tom] else [] end)}}') || return 1
        response=$(matrix_request -X PUT -H 'Content-Type: application/json' --data-binary "$payload" "$matrix_url/_matrix/client/v3/rooms/$room/send/m.room.message/nexus-alert-$(date +%s%N)-$$?user_id=$sender") || return 1
        jq -er '.event_id | select(type == "string" and startswith("$"))' <<<"$response"
      }
      if matrix_id=$(matrix_send "$1" "$2" 2>/dev/null); then
        if [ "$1" = normal ]; then printf '%s\n' "$matrix_id"; exit 0; fi
      else
        echo 'nexus-alert: Matrix delivery failed; sending ntfy fallback' >&2
      fi
      token=$(cat "$ntfy_token_file")
      curl -fsS -H @<(printf 'Authorization: Bearer %s\nPriority: %s\nTitle: %s\n' "$token" "$prio" "$title"; [ -z "$click" ] || printf 'Click: %s\n' "$click") \
        --data-binary "$2" "$ntfy_url/$1" | jq -r .id
    '';
  }))) (builtins.getAttr "ntfy-auth.env" config.sops.templates))) config.sops.placeholder)) config.myConfig.modules.nexus-alerts.sopsFile)) "http://${listen}")) "10.77.0.1:${builtins.toString port}")) 2586)) config.myConfig.modules.users.username)
