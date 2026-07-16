#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture=$'anthropic installed=yes authenticated=yes headroom=plenty\nopenai installed=yes authenticated=no headroom=unknown\nauto openai reason=preference'

[ "$(printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" anthropic)" = 'yes|yes|plenty' ]
[ "$(printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" openai)" = 'yes|no|unknown' ]
if printf '%s\n' "$fixture" | "$HERE/agent-provider-status.sh" missing >/dev/null 2>&1; then
  echo 'missing provider unexpectedly parsed' >&2
  exit 1
fi
if printf '%s\n' 'anthropic installed=yes authenticated=yes headroom=high' |
    "$HERE/agent-provider-status.sh" anthropic >/dev/null 2>&1; then
  echo 'invalid headroom vocabulary unexpectedly parsed' >&2
  exit 1
fi
printf 'ok: provider capability fields remain independent\n'
