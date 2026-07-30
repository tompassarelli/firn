#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
beagle_root="${BEAGLE_PATH:?firn-zig build smoke requires BEAGLE_PATH}"
fixture_root="$beagle_root/beagle-test/tests/fixtures/zig-multimodule"

for source in core.bclj bridge.bclj main.bclj; do
  if [ ! -f "$fixture_root/$source" ]; then
    echo "firn-zig build smoke: missing Beagle fixture $fixture_root/$source" >&2
    exit 1
  fi
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-zig-build-smoke.XXXXXX")"
cleanup() {
  rm -rf "${scratch:?}"
}
trap cleanup EXIT

BEAGLE_PATH="$beagle_root" \
FIRN_ZIG_OUT="$scratch/firn" \
  "$repo_root/firn-zig/build.sh" \
  "$fixture_root/core.bclj" \
  "$fixture_root/bridge.bclj" \
  "$fixture_root/main.bclj"

test -x "$scratch/firn"
test "$("$scratch/firn")" = "multi-module zig ok"

echo "firn-zig build smoke: ok"
