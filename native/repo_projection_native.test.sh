#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
: "${FIRN_RUNTIME_ROOT:?set FIRN_RUNTIME_ROOT to the candidate runtime}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-projection-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT
mkdir -p "$scratch/hosts" "$scratch/modules/sample"
cp "$repo/flake.bnix" "$scratch/flake.bnix"
cat >"$scratch/modules/sample/default.bnix" <<'SOURCE'
#lang beagle/nix
(ns default)
{:answer 42}
SOURCE
export FIRN_REPO="$scratch"
"$repo/dotfiles/bin/firn" repo build >"$scratch/build.out"
"$repo/dotfiles/bin/firn" repo diff all >"$scratch/clean.out"
mtime="$(stat -c %y "$scratch/modules/sample/default.nix")"
"$repo/dotfiles/bin/firn" repo build >"$scratch/repeat.out"
[[ "$(stat -c %y "$scratch/modules/sample/default.nix")" == "$mtime" ]]
printf 'deliberate output drift\n' >"$scratch/modules/sample/default.nix"
touch -d '2030-01-01 UTC' "$scratch/modules/sample/default.nix"
set +e
"$repo/dotfiles/bin/firn" repo diff modules/sample >"$scratch/drift.out"
status=$?
set -e
[[ "$status" == 1 ]]
rg -Fq -- '-deliberate output drift' "$scratch/drift.out"
[[ "$(<"$scratch/modules/sample/default.nix")" == 'deliberate output drift' ]]
"$repo/dotfiles/bin/firn" repo build >"$scratch/repair.out"
"$repo/dotfiles/bin/firn" repo diff all >"$scratch/repaired.out"
set +e
"$repo/dotfiles/bin/firn" repo diff --help >"$scratch/help.out" 2>&1
status=$?
set -e
[[ "$status" == 64 ]]
printf 'ok: real compiler detects newer-output drift, diff is read-only, build repairs it and preserves identical output\n'
