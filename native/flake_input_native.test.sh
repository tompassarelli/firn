#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'flake-input-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-flake-input-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'flake-input-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'flake-input-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

build_family() {
  local output="$scratch/build"
  mkdir -p "$output/node_modules/beagle"
  timeout --foreground 620 "$beagle/bin/beagle-build-all" "$@" \
    --out "$output" >"$scratch/build.out" 2>"$scratch/build.err" \
    || {
      sed -n '1,240p' "$scratch/build.err" >&2
      die "family compilation failed"
    }
  cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
    "$output/node_modules/beagle/core.js"
  cp -- "$beagle/beagle-lib/lib/beagle/host.js" \
    "$output/node_modules/beagle/host.js"
  printf '%s\n' '{"type":"module"}' \
    >"$output/node_modules/beagle/package.json"
  cp -- "$repo/native/flake_input_family_test_host.mjs" \
    "$output/flake_input_family_test_host.mjs"
}

datum="$beagle/native-core/src/beagle/datum_reader.bjs"
core="$repo/native/flake_input.bjs"
driver="$repo/native/flake_input_driver.bjs"

build_family "$datum" "$core" "$driver" \
  "$repo/native/flake_input_test.bjs" \
  "$repo/native/flake_input_driver_test.bjs" \
  "$repo/native/flake_input_family.bjs"

timeout --foreground 30 bun "$scratch/build/flake_input_family_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/driver.err" \
  || die "pure and driver test cases did not all pass"

make_fixture() {
  local root="$1"
  mkdir -p \
    "$root/modules/alpha" \
    "$root/modules/beta" \
    "$root/modules/plain"
  cat >"$root/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  (let [name "alpha"]
    {:flake-inputs
      {:zeta {:url "github:zeta/project"
              :inputs.nixpkgs.follows "nixpkgs"}
       :alpha {:url "github:alpha/project"}}}))
EOF
  cat >"$root/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:flake-inputs
    {:zeta {:url "github:zeta/project"
            :ignored "later declaration is coalesced"}}})
EOF
  cat >"$root/modules/plain/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:config {}})
EOF
  cp "$repo/docs/fixtures/flake-input-before.bnix" "$root/flake.bnix"
}

native_root="$scratch/native-repo"
make_fixture "$native_root"

run_once() {
  local result="$1"
  shift
  set +e
  timeout --foreground 30 "$@" >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

run_once "$scratch/native" \
  env -u FIRN_FLAKE_INPUTS_EMIT -u FIRN_TRACE_ID -u FIRN_TRACE_PATH \
    FIRN_REPO="$native_root" \
    env FIRN_FLAKE_INPUT_MODULE="$scratch/build/firn/flake-input-family.js" \
      bun "$repo/native/flake_input_host.mjs" flake-input resolve emit

[[ "$(<"$scratch/native.status")" == "0" ]] \
  || die "native command failed with status $(<"$scratch/native.status")"

diff -u "$repo/docs/fixtures/flake-input-expected.bnix" "$native_root/flake.bnix"
run_once "$scratch/native-second" \
  env FIRN_REPO="$native_root" \
    env FIRN_FLAKE_INPUT_MODULE="$scratch/build/firn/flake-input-family.js" \
      bun "$repo/native/flake_input_host.mjs" flake-input resolve emit
[[ "$(<"$scratch/native-second.status")" == "0" ]] \
  || die "second native run failed"
cmp -s "$repo/docs/fixtures/flake-input-expected.bnix" "$native_root/flake.bnix" \
  || die "idempotent run changed flake.bnix"
run_once "$scratch/invalid" env \
  FIRN_FLAKE_INPUT_MODULE="$scratch/build/firn/flake-input-family.js" \
  bun "$repo/native/flake_input_host.mjs" flake-input resolve show
[[ "$(<"$scratch/invalid.status")" == "64" ]] \
  || die "invalid grammar did not return 64"
[[ ! -s "$scratch/invalid.out" ]] || die "invalid grammar wrote stdout"

printf 'ok: flake-input emit matches recorded output, is idempotent and refuses conflicts or invalid input\n'
