usage() { echo 'usage: nexus-alert urgent|normal|socrates-test TEXT [TITLE] [CLICK]' >&2; exit 2; }
[ $# -ge 2 ] && [ $# -le 4 ] || usage
case "$1" in urgent) prio=5 ;; normal|socrates-test) prio=2 ;; *) usage ;; esac
title=${3:-Nexus}
click=${4:-}
token=$(cat "$NEXUS_ALERT_NTFY_TOKEN_FILE")
curl -fsS -H @<(printf 'Authorization: Bearer %s\nPriority: %s\nTitle: %s\n' "$token" "$prio" "$title"; [ -z "$click" ] || printf 'Click: %s\n' "$click") \
  --data-binary "$2" "$NEXUS_ALERT_NTFY_URL/$1" | jq -r .id
