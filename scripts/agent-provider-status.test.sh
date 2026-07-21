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
fixture_v3='{
  "schemaVersion": 3,
  "providers": [
    {
      "provider": "anthropic",
      "targets": [
        {"id":"a-exhausted","provider":"anthropic","installed":true,"authenticated":true,"available":true,"availabilityReason":"ready","routing":"exhausted","headroom":"exhausted"},
        {"id":"a-eligible","provider":"anthropic","installed":true,"authenticated":true,"available":true,"availabilityReason":"ready","routing":"eligible","headroom":"normal"}
      ]
    },
    {
      "provider": "openai",
      "targets": [
        {"id":"o-unavailable","provider":"openai","installed":true,"authenticated":false,"available":false,"availabilityReason":"authentication_missing","routing":"unavailable","headroom":"unknown"},
        {"id":"o-eligible","provider":"openai","installed":true,"authenticated":true,"available":true,"availabilityReason":"ready","routing":"eligible","headroom":"unknown"}
      ]
    }
  ]
}'

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

[ "$(printf '%s\n' "$fixture_v2" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|plenty|eligible' ]
[ "$(printf '%s\n' "$fixture_v2" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown|unavailable' ]
[ "$(printf '%s\n' "$fixture_v3" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|normal|eligible' ]
[ "$(printf '%s\n' "$fixture_v3" | "$HERE/agent-provider-status.sh" openai)" = 'yes|yes|unknown|eligible' ]

only_exhausted="$(printf '%s\n' "$fixture_v3" | jq '.providers[1].targets = [.providers[1].targets[0] | .id = "o-exhausted" | .authenticated = true | .available = true | .availabilityReason = "ready" | .routing = "exhausted" | .headroom = "exhausted"]')"
[ "$(printf '%s\n' "$only_exhausted" | "$HERE/agent-provider-status.sh" openai)" = 'yes|yes|exhausted|exhausted' ]
only_unavailable="$(printf '%s\n' "$fixture_v3" | jq '.providers[1].targets = [.providers[1].targets[0]]')"
[ "$(printf '%s\n' "$only_unavailable" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown|unavailable' ]

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
assert_rejected 'v3 exhausted route without exhausted headroom' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[0].targets[0].headroom = "normal"')"
assert_rejected 'v3 eligible route with exhausted headroom' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[0].targets[1].headroom = "exhausted"')"
assert_rejected 'v3 unavailable route marked available' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[1].targets[0].available = true')" openai
assert_rejected 'v3 target with wrong provider identity' \
  "$(printf '%s\n' "$fixture_v3" | jq '.providers[1].targets[0].provider = "anthropic"')" openai
assert_rejected 'v3 target missing availability' \
  "$(printf '%s\n' "$fixture_v3" | jq 'del(.providers[1].targets[0].available)')" openai

printf 'ok: north providers schemas v2/v3 distinguish eligible, exhausted, unavailable, and malformed targets\n'
