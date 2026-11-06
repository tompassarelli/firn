#!/usr/bin/env bash
set -euo pipefail
unit=$(<"$1")
grep -q '"Slice":"agent.slice"' <<<"$unit" || { echo "north-land@north runs outside agent.slice: $unit" >&2; exit 1; }
if grep -q 'SAFE_PUSH_LAND_RUNNER=' <<<"$unit"; then
  echo "north-land@north overrides the repositories' land-check runner" >&2
  exit 1
fi
