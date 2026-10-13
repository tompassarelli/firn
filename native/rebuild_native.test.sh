#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-rebuild-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'rebuild-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'rebuild-native: %s\n' "$*" >&2
  exit 1
}

bun="${FIRN_BUN:-$(command -v bun || true)}"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

timeout --foreground 30 env \
  FIRN_REBUILD_TEST_MODULE="$repo/native/rebuild_test.ts" \
  "$bun" "$repo/native/firn_rebuild_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "seeded rebuild properties failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

printf 'ok: seeded rebuild ordering, platform and failure-prefix properties pass\n'
