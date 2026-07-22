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

source_file=$here/default.bnix
generated_file=$here/default.nix
for file in "$source_file" "$generated_file"; do
  grep -Fq 'northProduction' "$file"
  grep -Fq 'northMcpProduction' "$file"
  grep -Fq 'northDev' "$file"
  grep -Fq 'northMcpDev' "$file"
  grep -Fq 'provenance=checkout path=$target' "$file"
  grep -Fq 'pinnedCommandNames' "$file"
  grep -Fq 'pinnedCommands' "$file"
done

[ "$(grep -c 'exec /run/current-system/sw/bin/north-coord-runtime exec-checkout' "$source_file")" -eq 1 ]
[ "$(grep -c '(s "exec " northPkg "/bin/north' "$source_file")" -eq 4 ]
[ "$(grep -c 'unset NORTH_CHECKOUT' "$source_file")" -eq 5 ]
grep -Fq '"north-on-stop" "concern" "north-stream-sync"' "$source_file"

printf 'ok: ordinary North/MCP and lifecycle commands are package-bound; checkout execution is explicit *-dev provenance\n'
