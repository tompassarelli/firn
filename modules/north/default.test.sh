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
exec_stage=$here/north-checkout-exec
for file in "$source_file" "$generated_file"; do
  grep -Fq 'northCheckout' "$file"
  grep -Fq 'northMcpCheckout' "$file"
  grep -Fq 'northDev' "$file"
  grep -Fq 'northMcpDev' "$file"
  grep -Fq 'northPackaged' "$file"
  grep -Fq 'northMcpPackaged' "$file"
  grep -Fq 'provenance=checkout path=$target' "$file"
  grep -Fq 'pinnedCommandNames' "$file"
  grep -Fq 'pinnedCommands' "$file"
  # Ordinary north/north-mcp resolve the checkout and hand off to the pinned
  # runtime; the runtime contract itself is never restated module-side.
  grep -Fq 'NORTH_CHECKOUT:-$HOME/code/north/main' "$file"
  grep -Fq 'NORTH_CHECKOUT_TARGET' "$file"
  grep -Fq 'north-checkout-exec' "$file"
  grep -Fq 'north-env' "$file"
done

# Only the legacy *-dev shims still delegate to the Fram runtime selector; the
# ordinary commands must not, or North's channel recouples to Fram's.
[ "$(grep -c 'exec /run/current-system/sw/bin/north-coord-runtime exec-checkout' "$source_file")" -eq 1 ]
# The packaged flake bin is reachable ONLY through the two *-packaged hatches
# (north + north-mcp) and the pinned lifecycle commands.
[ "$(grep -c '(s "exec " northPkg "/bin/north' "$source_file")" -eq 2 ]
[ "$(grep -c 'unset NORTH_CHECKOUT' "$source_file")" -eq 3 ]
grep -Fq '"north-on-stop" "concern" "north-stream-sync"' "$source_file"
grep -Fq 'northPackaged northMcpPackaged' "$source_file"

# Checkout provenance is asserted by the second stage, not by the runtime env.
grep -Fq 'export NORTH_PACKAGE_MODE=checkout' "$exec_stage"
grep -Fq 'describe --always --dirty' "$exec_stage"
grep -Fq 'export NORTH_BIN="$checkout/bin/north"' "$exec_stage"
if grep -q 'north-coord-runtime' "$exec_stage"; then
  printf 'checkout execution stage delegates to the Fram runtime selector\n' >&2
  exit 1
fi

printf 'ok: ordinary North/MCP execute the checkout on the pinned runtime; lifecycle hooks and *-packaged stay package-bound\n'
