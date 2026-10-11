#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$({
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  })" || {
    printf 'rebuild-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
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

[[ -x "$beagle/bin/beagle-build-all" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

modules="$scratch/modules"
json="$beagle/native-core/src/native/json.bjs"
timeout --foreground 120 "$beagle/bin/beagle-build-all" \
  "$json" \
  "$repo/native/impact.bjs" \
  "$repo/native/rebuild.bjs" \
  "$repo/native/rebuild_test.bjs" \
  "$repo/native/rebuild_native.bjs" \
  "$repo/native/firn_rebuild_family.bjs" \
  --out "$modules" \
  >"$scratch/rebuild.build.out" 2>"$scratch/rebuild.build.err" \
  || {
    sed -n '1,240p' "$scratch/rebuild.build.err" >&2
    die "rebuild module compilation failed"
  }

mkdir -p "$scratch/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" "$beagle/beagle-lib/lib/beagle/host.js" \
  "$scratch/node_modules/beagle/"
printf '%s\n' '{"type":"module"}' >"$scratch/node_modules/beagle/package.json"

bun="${FIRN_BUN:-$(command -v bun || true)}"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

timeout --foreground 30 env \
  FIRN_REBUILD_TEST_MODULE="$modules/firn/rebuild-test.js" \
  "$bun" "$repo/native/firn_rebuild_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "seeded rebuild property or impact boundary failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

printf 'ok: seeded rebuild ordering, platform and failure-prefix properties pass\n'
