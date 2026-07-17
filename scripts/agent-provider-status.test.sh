#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture='{
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

[ "$(printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|plenty' ]
[ "$(printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown' ]
if printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" missing >/dev/null 2>&1; then
  echo 'missing provider unexpectedly parsed' >&2
  exit 1
fi
if printf '%s\n' "$fixture" | jq '.providers[0].targets[0].headroom = "high"' |
    "$HERE/agent-provider-status.sh" anthropic >/dev/null 2>&1; then
  echo 'invalid headroom vocabulary unexpectedly parsed' >&2
  exit 1
fi
if printf '%s\n' "$fixture" | jq '.schemaVersion = 1' |
    "$HERE/agent-provider-status.sh" anthropic >/dev/null 2>&1; then
  echo 'unknown schema version unexpectedly parsed' >&2
  exit 1
fi
printf 'ok: provider capability fields remain independent\n'
