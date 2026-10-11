#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
beagle="${BEAGLE_PATH:?BEAGLE_PATH must name the Beagle checkout}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-repo-build-family.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'repo-build-family: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'repo-build-family: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

build_family() {
  local output="$scratch/build"
  mkdir -p "$output/node_modules/beagle"
  timeout --foreground 180 "$beagle/bin/beagle-build-all" "$@" \
    --out "$output" >"$scratch/build.out" 2>"$scratch/build.err" \
    || {
      sed -n '1,240p' "$scratch/build.err" >&2
      die "Beagle/JS graph compilation failed"
    }
  cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
    "$output/node_modules/beagle/core.js"
  cp -- "$beagle/beagle-lib/lib/beagle/host.js" \
    "$output/node_modules/beagle/host.js"
  printf '%s\n' '{"type":"module"}' \
    >"$output/node_modules/beagle/package.json"
  cp -- "$repo/native/repo_build_family_test_host.mjs" \
    "$output/repo_build_family_test_host.mjs"
  [[ -f "$output/firn/repo-build-family.js" ]] \
    || die "compiled repo-build family module is unavailable"
}

core="$repo/native/repo_build.bjs"
datum="$beagle/native-core/src/beagle/datum_reader.bjs"
json="$beagle/native-core/src/native/json.bjs"
tag_resolve="$repo/native/tag_resolve.bjs"
tag_inputs="$repo/native/tag_inputs.bjs"
tag_driver="$repo/native/tag_resolve_driver.bjs"
tag_family="$repo/native/tag_resolve_family.bjs"
flake_input="$repo/native/flake_input.bjs"
flake_driver="$repo/native/flake_input_driver.bjs"
flake_family="$repo/native/flake_input_family.bjs"
inventory="$repo/native/inventory.bjs"
inventory_family="$repo/native/inventory_family.bjs"

build_family \
  "$datum" "$json" "$tag_resolve" "$tag_inputs" "$tag_driver" \
  "$tag_family" \
  "$flake_input" "$flake_driver" "$flake_family" \
  "$inventory" "$inventory_family" \
  "$core" "$repo/native/repo_build_test.bjs" \
  "$repo/native/repo_build_family.bjs"

timeout --foreground 60 bun \
  "$scratch/build/repo_build_family_test_host.mjs" \
  >"$scratch/scenarios.out" 2>"$scratch/scenarios.err" \
  || {
    sed -n '1,240p' "$scratch/scenarios.err" >&2
    die "repo-build policy scenarios failed"
  }

galileo="galileo"
[[ -x "${FIRN_RUNTIME_BIN:-}/galileo" ]] && galileo="$FIRN_RUNTIME_BIN/galileo"
command -v "$galileo" >/dev/null \
  || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"
(cd "$repo" && timeout --foreground 120 "$galileo" check) \
  >"$scratch/budget.out" 2>"$scratch/budget.err" \
  || {
    sed -n '1,240p' "$scratch/budget.out" "$scratch/budget.err" >&2
    die "galileo check boot-coupling budget failed"
  }

printf 'ok: real repository boot-coupling budget and policy checks pass\n'
