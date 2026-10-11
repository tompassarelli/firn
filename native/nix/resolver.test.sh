#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
beagle="${BEAGLE_PATH:?set BEAGLE_PATH to the repository compiler}"
workbench="${1:?pass the clause-workbench executable built from config/clause-revision}"
output="$repo/.firn-build/nix-resolver"
mkdir -p "$output/node_modules/beagle"
fixture="$(mktemp -d "$repo/.firn-build/nix-resolver-fixture.XXXXXX")"
mkdir -p "$fixture/native/nix" "$fixture/modules"

sources=(
  "$beagle/native-core/src/beagle/datum_reader.bjs"
  "$beagle/native-core/src/native/json.bjs"
)
for source in tag_resolve tag_inputs tag_resolve_driver tag_resolve_family \
  tag_commands tag_commands_driver tag_commands_family firn_tag_family \
  flake_input flake_input_driver flake_input_family repo_build repo_build_family; do
  sources+=("$repo/native/$source.bjs")
done
"$beagle/bin/beagle-build-all" "${sources[@]}" --out "$output"
cp "$beagle/beagle-lib/lib/beagle/core.js" "$beagle/beagle-lib/lib/beagle/host.js" \
  "$output/node_modules/beagle/"
printf '%s\n' '{"type":"module"}' >"$output/node_modules/beagle/package.json"

export FIRN_REPO="$fixture"
export FIRN_TAG_MODULE="$output/firn/tag-family.js"
export FIRN_REPO_BUILD_MODULE="$output/firn/repo-build-family.js"
export FIRN_CLAUSE_WORKBENCH="$workbench"

cp "$repo/native/module_metadata.clause" "$fixture/native/"
cp "$here/nixpkgs.clause" "$fixture/native/nix/"
for name in btop jq gnome-keyring kitty ladybird; do
  mkdir -p "$fixture/modules/$name"
  cp "$here/$name.clause" "$fixture/native/nix/"
  cp "$repo/modules/$name/tags.clause" "$fixture/modules/$name/"

done

mkdir -p "$fixture/hosts/fixture"
cat >"$fixture/hosts/fixture/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
{:platform linux :enabled [terminal browsers cli-tools] :disabled []}
EOF
export FIRN_HOST=fixture
bun "$repo/native/firn_tag_host.mjs" tag status fixture >"$output/default.out"
if rg -x '  (kitty|ladybird)' "$output/default.out"; then
  printf 'resolver: opt-in module enabled by default tag\n' >&2
  exit 1
fi
bun "$repo/native/firn_tag_host.mjs" tag opt-in terminal+kitty
bun "$repo/native/firn_tag_host.mjs" tag opt-in browsers+ladybird
bun "$repo/native/firn_tag_host.mjs" tag status fixture >"$output/opt-in.out"
rg -x '  kitty' "$output/opt-in.out"
rg -x '  ladybird' "$output/opt-in.out"

cat >"$fixture/flake.bnix" <<'EOF'
#lang beagle/nix
(ns flake)
;; --- GENERATED MODULE INPUTS (do not edit) ---
;; --- END GENERATED MODULE INPUTS ---
;; --- GENERATED MODULE ARGS (do not edit) ---
;; --- END GENERATED MODULE ARGS ---
;; --- GENERATED MODULE SPECIALARGS (do not edit) ---
;; --- END GENERATED MODULE SPECIALARGS ---
;; --- GENERATED HM SPECIALARGS (do not edit) ---
;; --- END GENERATED HM SPECIALARGS ---
;; --- GENERATED DARWIN SPECIALARGS (do not edit) ---
;; --- END GENERATED DARWIN SPECIALARGS ---
;; --- GENERATED DARWIN HM SPECIALARGS (do not edit) ---
;; --- END GENERATED DARWIN HM SPECIALARGS ---
{}
EOF
bun "$repo/native/repo_build_host.mjs" repo build
bun "$repo/native/repo_build_host.mjs" repo diff native/nix >"$output/diff.out"

cat >"$fixture/modules/btop/tags.clause" <<'EOF'
export metadata(): F64
  42.0
EOF
if bun "$repo/native/firn_tag_host.mjs" tag show btop >"$output/type.out" 2>"$output/type.err"; then
  printf 'resolver: non-text tag result was accepted\n' >&2
  exit 1
fi
cp "$repo/modules/btop/tags.clause" "$fixture/modules/btop/"

git -C "$repo" show fe9f50f4:modules/fd/default.bnix >"$fixture/modules/btop/default.bnix"
if bun "$repo/native/firn_tag_host.mjs" tag show btop >"$output/conflict.out" 2>"$output/conflict.err"; then
  printf 'resolver: competing module sources were accepted\n' >&2
  exit 1
fi
rm "$fixture/modules/btop/default.bnix" "$fixture/native/nix/btop.clause"
if bun "$repo/native/firn_tag_host.mjs" tag show btop >"$output/missing.out" 2>"$output/missing.err"; then
  printf 'resolver: missing Clause source was accepted\n' >&2
  exit 1
fi
rg -F 'native/nix/btop.clause' "$output/missing.err"
"$here/compare.test.sh" "$workbench" "$fixture"
printf 'ok: Clause discovery, compilation, tags, evaluation, and source ownership\n'
