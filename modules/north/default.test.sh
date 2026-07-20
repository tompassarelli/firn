#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
guard=$here/north-runtime-owner-guard

"$guard" status
"$guard" agents --json
"$guard" up --check-runtime

for invocation in 'up' 'up --restart' 'up --unexpected'; do
  read -r -a args <<<"$invocation"
  if output=$("$guard" "${args[@]}" 2>&1); then
    printf 'systemd ownership guard accepted direct lifecycle command: north %s\n' "$invocation" >&2
    exit 1
  fi
  grep -Fq 'owned by north-coord.service' <<<"$output"
  grep -Fq 'sudo systemctl restart north-coord.service' <<<"$output"
done

printf 'ok: Firn ordinary North wrapper rejects direct coordinator lifecycle before checkout execution\n'
