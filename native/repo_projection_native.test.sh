#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
: "${FIRN_RUNTIME_ROOT:?set FIRN_RUNTIME_ROOT to the candidate runtime}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-projection-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT
mkdir -p "$scratch/hosts" "$scratch/modules/sample" "$scratch/config"
git init -q -b main "$scratch"
printf '{ inputs = {}; outputs = _: {}; }\n' >"$scratch/flake.nix"
printf '{ ... }: { answer = 42; }\n' >"$scratch/modules/sample/default.nix"
export FIRN_REPO="$scratch"
"$repo/dotfiles/bin/firn" repo build >"$scratch/build.out"
"$repo/dotfiles/bin/firn" repo diff all >"$scratch/clean.out"
mtime="$(stat -c %y "$scratch/modules/sample/default.nix")"
"$repo/dotfiles/bin/firn" repo build >"$scratch/repeat.out"
[[ "$(stat -c %y "$scratch/modules/sample/default.nix")" == "$mtime" ]]
printf '{ deliberate syntax failure\n' >"$scratch/modules/sample/default.nix"
set +e
"$repo/dotfiles/bin/firn" repo diff modules/sample >"$scratch/drift.out" 2>"$scratch/drift.err"
status=$?
set -e
[[ "$status" != 0 ]]
rg -Fq 'syntax error' "$scratch/drift.err"
[[ "$(<"$scratch/modules/sample/default.nix")" == '{ deliberate syntax failure' ]]
printf '{ ... }: { answer = 42; }\n' >"$scratch/modules/sample/default.nix"
"$repo/dotfiles/bin/firn" repo build >"$scratch/repair.out"
"$repo/dotfiles/bin/firn" repo diff all >"$scratch/repaired.out"
set +e
"$repo/dotfiles/bin/firn" repo diff --help >"$scratch/help.out" 2>&1
status=$?
set -e
[[ "$status" == 64 ]]
printf 'ok: Nix source validation rejects syntax errors, diff preserves source, and repeated builds preserve identical source\n'
