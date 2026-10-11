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

core="$repo/native/flake_input.bjs"
driver="$repo/native/flake_input_driver.bjs"

command -v galileo >/dev/null || [[ -x "${FIRN_RUNTIME_BIN:-}/galileo" ]] \
  || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"

build_family "$core" "$driver" \
  "$repo/native/flake_input_driver_test.bjs" \
  "$repo/native/flake_input_family.bjs"

timeout --foreground 30 bun "$scratch/build/flake_input_family_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/driver.err" \
  || die "driver test cases did not all pass"

module() {
  local root="$1" name="$2"
  shift 2
  mkdir -p "$root/modules/$name"
  {
    printf 'use firn/tags\n\n%s is a Module\n' "$name"
    for url in "$@"; do
      printf '%s needs flake input %s\n' "$name" "$url"
    done
  } >"$root/modules/$name/default.gal"
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/config"
  printf 'use firn/tags\n\ncli-tools is a Tag\n' >"$root/config/tags.gal"
  module "$root" alpha '"zeta" from "github:zeta/project"' \
    '"alpha" from "github:alpha/project"'
  module "$root" beta '"zeta" from "github:zeta/project"'
  module "$root" plain
  cat >"$root/flake.gal" <<'EOF'
use firn/tags

given flake input {name: Text} follows {input: Text} from {target: Text}

flake input "zeta" follows "nixpkgs" from "nixpkgs"

nix file
  value
    inputs
      nixpkgs
        url: "github:nixos/nixpkgs/nixos-26.05"
      for ?name, ?url where ?name flake input url ?url
        {?name}
          for ?input, ?target where flake input ?name follows ?input from ?target
            inputs.{?input}.follows: ?target
          url: ?url
    outputs: ({self, nixpkgs, for ?n where ?n flake input url ?_: `{?n}`, ...}) => {lib.mkSystem: nixpkgs.lib.nixosSystem({specialArgs: {inputs: {for ?n where ?n flake input url ?_: {?n}: `{?n}`}}})}
EOF
}

native_root="$scratch/native-repo"
make_fixture "$native_root"

run_once() {
  local result="$1"
  shift
  set +e
  timeout --foreground 60 "$@" >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

emit() {
  run_once "$1" env FIRN_REPO="$2" \
    FIRN_FLAKE_INPUT_MODULE="$scratch/build/firn/flake-input-family.js" \
    bun "$repo/native/flake_input_host.mjs" flake-input resolve emit
}

expected="$repo/docs/fixtures/flake-input-expected.nix"

emit "$scratch/native" "$native_root"
[[ "$(<"$scratch/native.status")" == "0" ]] \
  || die "native command failed with status $(<"$scratch/native.status")"
diff -u "$expected" "$native_root/flake.nix"
grep -qx '  zeta (from alpha)' "$scratch/native.out" \
  || die "summary does not name alpha as zeta's first module"
grep -qx 'flake-inputs: updated flake.nix' "$scratch/native.out" \
  || die "first run did not report the update"

emit "$scratch/native-second" "$native_root"
[[ "$(<"$scratch/native-second.status")" == "0" ]] || die "second native run failed"
cmp -s "$expected" "$native_root/flake.nix" || die "idempotent run changed flake.nix"
grep -qx 'flake-inputs: flake.nix is up to date' "$scratch/native-second.out" \
  || die "second run did not report up to date"

module "$native_root" beta '"zeta" from "github:other/project"'
emit "$scratch/conflict" "$native_root"
[[ "$(<"$scratch/conflict.status")" == "1" ]] || die "conflicting urls did not fail"
[[ ! -s "$scratch/conflict.out" ]] || die "conflict wrote a summary"
grep -q 'two values for "zeta"' "$scratch/conflict.err" \
  || die "conflict diagnostic does not name zeta"
cmp -s "$expected" "$native_root/flake.nix" || die "conflict changed flake.nix"

run_once "$scratch/invalid" env \
  FIRN_FLAKE_INPUT_MODULE="$scratch/build/firn/flake-input-family.js" \
  bun "$repo/native/flake_input_host.mjs" flake-input resolve show
[[ "$(<"$scratch/invalid.status")" == "64" ]] \
  || die "invalid grammar did not return 64"
[[ ! -s "$scratch/invalid.out" ]] || die "invalid grammar wrote stdout"

printf 'ok: flake-input emit builds flake.gal to the recorded flake.nix, is idempotent and refuses conflicts or invalid input\n'
