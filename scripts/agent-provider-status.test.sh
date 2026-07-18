#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture_v2='{
  "schemaVersion": 2,
  "providers": [
    {
      "provider": "anthropic",
      "targets": [
        {"installed": true, "authenticated": true, "routing": "eligible", "headroom": "normal"},
        {"installed": true, "authenticated": true, "routing": "eligible", "headroom": "plenty"}
      ]
    },
    {
      "provider": "openai",
      "targets": [
        {"installed": true, "authenticated": false, "routing": "unavailable", "headroom": "unknown"}
      ]
    }
  ],
  "diagnosticRouteProbe": {"available": true, "provider": "anthropic"}
}'
fixture_v3="$(printf '%s\n' "$fixture_v2" | jq '.schemaVersion = 3')"

assert_rejected() {
  local label="$1"
  local document="$2"
  local provider="${3:-anthropic}"

  if printf '%s\n' "$document" |
      "$HERE/agent-provider-status.sh" "$provider" >/dev/null 2>&1; then
    printf '%s unexpectedly parsed\n' "$label" >&2
    exit 1
  fi
}

[ "$(printf '%s\n' "$fixture_v2" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|plenty' ]
[ "$(printf '%s\n' "$fixture_v2" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown' ]
[ "$(printf '%s\n' "$fixture_v3" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|plenty' ]
[ "$(printf '%s\n' "$fixture_v3" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown' ]

assert_rejected 'missing provider' "$fixture_v3" missing
assert_rejected 'invalid headroom vocabulary' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[0].targets[0].headroom = "high"')"
assert_rejected 'schema version 1' \
  "$(printf '%s\n' "$fixture_v3" | jq '.schemaVersion = 1')"
assert_rejected 'schema version 4' \
  "$(printf '%s\n' "$fixture_v3" | jq '.schemaVersion = 4')"
assert_rejected 'malformed v3 provider group' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[0].targets = {}')"
assert_rejected 'malformed v3 target' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[0].targets[0].authenticated = "true"')"

printf 'ok: north providers schemas v2/v3 preserve strict capability parsing\n'
