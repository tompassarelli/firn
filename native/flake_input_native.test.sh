#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
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




timeout --foreground 30 bun "$repo/native/flake_input_family_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/driver.err" \
  || die "driver test cases did not all pass"

module() {
  local root="$1" name="$2"
  shift 2
  mkdir -p "$root/modules/$name"
  bun - "$root/modules/$name/metadata.json" "$@" <<'JS'
import {writeFileSync} from 'node:fs';
const [path,...facts]=process.argv.slice(2), flakeInputs={};
for (const fact of facts) {
  const [,name,url] = /^"([^"\n]+)" from "([^"\n]+)"$/.exec(fact);
  flakeInputs[name]=url;
}
writeFileSync(path,JSON.stringify({flakeInputs},null,2)+'\n');
JS
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/config"
  git init -q -b main "$root"
  module "$root" alpha '"zeta" from "github:zeta/project"' '"alpha" from "github:alpha/project"'
  module "$root" beta '"zeta" from "github:zeta/project"'
  module "$root" plain
  cat >"$root/flake.nix" <<'EOF'
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    zeta = {
      url = "github:old/project";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs: { inherit inputs; };
}
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
    FIRN_FLAKE_INPUT_MODULE="$repo/native/flake_input_family.ts" \
    bun "$repo/native/flake_input_host.mjs" flake-input resolve emit
}

expected="$repo/docs/fixtures/flake-input-expected.nix"

emit "$scratch/native" "$native_root"
[[ "$(<"$scratch/native.status")" == "0" ]] \
  || die "native command failed with status $(<"$scratch/native.status")"
nix-instantiate --eval --strict --json --expr "(import $expected).inputs" >"$scratch/expected.inputs"
nix-instantiate --eval --strict --json --expr "(import $native_root/flake.nix).inputs" >"$scratch/actual.inputs"
cmp "$scratch/expected.inputs" "$scratch/actual.inputs"
cp "$native_root/flake.nix" "$scratch/resolved.nix"
grep -qx '  zeta (from alpha)' "$scratch/native.out" \
  || die "summary does not name alpha as zeta's first module"
grep -qx 'flake-inputs: updated flake.nix' "$scratch/native.out" \
  || die "first run did not report the update"

emit "$scratch/native-second" "$native_root"
[[ "$(<"$scratch/native-second.status")" == "0" ]] || die "second native run failed"
cmp -s "$scratch/resolved.nix" "$native_root/flake.nix" || die "idempotent run changed flake.nix"
grep -qx 'flake-inputs: flake.nix is up to date' "$scratch/native-second.out" \
  || die "second run did not report up to date"

module "$native_root" beta '"zeta" from "github:other/project"'
emit "$scratch/conflict" "$native_root"
[[ "$(<"$scratch/conflict.status")" == "1" ]] || die "conflicting urls did not fail"
[[ ! -s "$scratch/conflict.out" ]] || die "conflict wrote a summary"
grep -q "conflicting URLs for 'zeta'" "$scratch/conflict.err" \
  || die "conflict diagnostic does not name zeta"
cmp -s "$scratch/resolved.nix" "$native_root/flake.nix" || die "conflict changed flake.nix"

run_once "$scratch/invalid" env \
  FIRN_FLAKE_INPUT_MODULE="$repo/native/flake_input_family.ts" \
  bun "$repo/native/flake_input_host.mjs" flake-input resolve show
[[ "$(<"$scratch/invalid.status")" == "64" ]] \
  || die "invalid grammar did not return 64"
[[ ! -s "$scratch/invalid.out" ]] || die "invalid grammar wrote stdout"

printf 'ok: flake-input emit synchronizes the recorded flake input declarations, is idempotent and refuses conflicts or invalid input\n'
