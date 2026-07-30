#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -n "${BEAGLE_PATH:-}" ]; then
  beagle="$BEAGLE_PATH/bin/beagle"
elif command -v beagle-dev >/dev/null 2>&1; then
  beagle="$(command -v beagle-dev)"
elif command -v beagle >/dev/null 2>&1; then
  beagle="$(command -v beagle)"
else
  echo "firn-zig-build: Beagle executable not found" >&2
  echo "  set BEAGLE_PATH to a Beagle checkout" >&2
  exit 1
fi

if [ ! -x "$beagle" ]; then
  echo "firn-zig-build: beagle executable not found at $beagle" >&2
  echo "  set BEAGLE_PATH to a Beagle checkout" >&2
  exit 1
fi

output="${FIRN_ZIG_OUT:-$repo_root/firn-zig/zig-out/bin/firn}"
if [ "$#" -eq 0 ]; then
  set -- "$repo_root/firn-zig/src/firn/main.bzig"
fi

if [ -n "${BEAGLE_PATH:-}" ] &&
   [ -f "$BEAGLE_PATH/.envrc" ] &&
   command -v direnv >/dev/null 2>&1; then
  exec direnv exec "$BEAGLE_PATH" \
    "$beagle" build --target zig --exe "$output" "$@"
fi

exec "$beagle" build --target zig --exe "$output" "$@"
