#!/usr/bin/env bash
set -euo pipefail

bun=${FIRN_BUN:-$(command -v bun)}
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/firn-host-list-clause.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

compare() {
  local data_root=$1 label=$2 expected_status=$3
  shift 3
  local actual_status=0
  FIRN_REPO="$data_root" FIRN_BUN="$bun" FIRN_RUNTIME_ROOT="${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}" \
    "$repo/dotfiles/bin/firn" "$@" >"$scratch/actual.out" 2>"$scratch/actual.err" \
    || actual_status=$?
  [[ $actual_status -eq $expected_status ]]
  printf 'ok: %s\n' "$label"
}

mkdir -p "$scratch/multiple/hosts/zeta" "$scratch/multiple/hosts/alpha" "$scratch/multiple/hosts/mid"
: >"$scratch/multiple/hosts/plain-file"
ln -s zeta "$scratch/multiple/hosts/link"
compare "$scratch/multiple" directories-only 0 host list all
printf 'Hosts (3):\n  alpha\n  mid\n  zeta\n' >"$scratch/expected.out"
cmp "$scratch/actual.out" "$scratch/expected.out"
[[ ! -s "$scratch/actual.err" ]]

mkdir -p "$scratch/single/hosts/solo" "$scratch/empty/hosts" "$scratch/missing" "$scratch/bad"
compare "$scratch/single" single 0 host list
compare "$scratch/empty" empty 0 host list all
compare "$scratch/missing" missing 0 host list
: >"$scratch/bad/hosts"
compare "$scratch/bad" ENOTDIR 1 host list all
[[ ! -s "$scratch/actual.out" ]]

compare "${FIRN_REAL_REPO:-$HOME/code/nixos-config/main}" real-repository 0 host list all # hardcoded-repo-path:allow
