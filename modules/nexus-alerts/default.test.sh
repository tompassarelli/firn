#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
cat >"$work/bin/curl" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 1 ]; do
  case "$1" in -H) shift; [[ $1 == @* ]] && cat "${1#@}" >>"$CURL_LOG" ;; esac
  shift
done
printf 'URL: %s\n' "$1" >>"$CURL_LOG"
printf '{"id":"fixture"}\n'
SH
chmod +x "$work/bin/curl"
printf 'fixture-token\n' >"$work/token"
export PATH="$work/bin:$PATH" NEXUS_ALERT_NTFY_URL=http://ntfy.fixture NEXUS_ALERT_NTFY_TOKEN_FILE="$work/token"

for case in urgent:5 normal:2 socrates-test:2; do
  topic=${case%:*}
  export CURL_LOG="$work/$topic.log"
  [[ "$(bash "$here/nexus-alert.sh" "$topic" text title)" == fixture ]]
  grep -qx "Priority: ${case#*:}" "$CURL_LOG"
  grep -qx "URL: http://ntfy.fixture/$topic" "$CURL_LOG"
done
if bash "$here/nexus-alert.sh" chat text 2>/dev/null; then echo 'unknown topic was accepted' >&2; exit 1; fi
printf 'ok: nexus-alert publishes urgent at priority 5 and normal and test at priority 2, rejects other topics\n'
