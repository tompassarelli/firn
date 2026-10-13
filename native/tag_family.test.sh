#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-tag-family.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'tag-family: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'tag-family: %s\n' "$*" >&2
  exit 1
}

command -v bun >/dev/null 2>&1 || die "Bun is unavailable"
command -v galileo >/dev/null || [[ -x "${FIRN_RUNTIME_BIN:-}/galileo" ]] \
  || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"



run_once() {
  local result="$1"
  shift
  set +e
  timeout --foreground 30 "$@" >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

assert_status() {
  local result="$1" expected="$2" label="$3"
  [[ "$(<"$result.status")" == "$expected" ]] \
    || die "$label returned $(<"$result.status"), expected $expected"
}

assert_empty() {
  local file="$1" label="$2"
  [[ ! -s "$file" ]] || die "$label was not empty"
}

assert_same() {
  local expected="$1" actual="$2" label="$3"
  cmp -s "$expected" "$actual" || {
    diff -u "$expected" "$actual" >&2 || true
    die "$label changed"
  }
}

printf 'tag-family: checking seeded algebra and mutation properties (seed 73421)\n' >&2
timeout --foreground 30 bun --eval '
  const resolve = await import(process.argv[1]);
  const mutation = await import(process.argv[2]);
  process.exitCode = resolve["runProperties"](process.env.CI ? 512 : 128) + mutation["runProperties"](process.env.CI ? 512 : 128);
' "$repo/native/tag_resolve_property_test.ts" \
  "$repo/native/tag_mutation_property_test.ts" \
  || die "seeded tag properties failed"
runtime=(env FIRN_TAG_MODULE="$repo/native/firn_tag_family.ts" \
  bun "$repo/native/firn_tag_host.mjs")

make_fixture() {
  local root="$1" host="${2:-fixture}"
  mkdir -p \
    "$root/modules/alpha" \
    "$root/modules/beta" \
    "$root/modules/delta" \
    "$root/modules/epsilon" \
    "$root/modules/gamma" \
    "$root/modules/plain" \
    "$root/hosts/$host"
  git init -q -b main "$root"
  cat >"$root/flake.bnix" <<'EOF'
#lang beagle/nix
(ns flake)
{}
EOF
  mkdir -p "$root/config"
  cat >"$root/config/tags.gal" <<'EOF'
use firn/tags

creative is a Tag
desktop is a Tag
terminal is a Tag
alpha is a Module
beta is a Module
delta is a Module
epsilon is a Module
gamma is a Module
plain is a Module
alpha is tagged desktop
alpha is tagged terminal
beta is tagged desktop
delta can opt into desktop
epsilon is tagged creative
epsilon can opt into desktop
gamma is tagged terminal
linux is a Platform
linux allows every module
EOF
  cat >"$root/hosts/$host/_generated-enables.gal" <<EOF
use firn/tags

$host is a Host
$host runs linux
$host enables desktop
$host drops beta from desktop
$host adds delta to desktop
$host enables terminal
$host disables gamma
EOF
}

run_native() {
  local result="$1" root="$2" host="$3"
  shift 3
  run_once "$result" env FIRN_REPO="$root" FIRN_HOST="$host" \
    "${runtime[@]}" "$@"
}

printf 'tag-family: checking structured inventory boundary\n' >&2
inventory_root="$scratch/inventory-repo"
make_fixture "$inventory_root"

cat >"$scratch/index.expected" <<'EOF'
{"name":"alpha","tags":["desktop","terminal"],"tags_opt_in":[]}
{"name":"beta","tags":["desktop"],"tags_opt_in":[]}
{"name":"delta","tags":[],"tags_opt_in":["desktop"]}
{"name":"epsilon","tags":["creative"],"tags_opt_in":["desktop"]}
{"name":"gamma","tags":["terminal"],"tags_opt_in":[]}
{"name":"plain","tags":[],"tags_opt_in":[]}
EOF
run_native "$scratch/index-stdout" "$inventory_root" fixture tag index stdout
assert_status "$scratch/index-stdout" 0 "tag index stdout"
bun - "$scratch/index.expected" "$scratch/index-stdout.out" <<'JS'
import assert from 'node:assert/strict';
const rows = async path => (await Bun.file(path).text()).trim().split('\n').map(JSON.parse);
assert.deepEqual(await rows(process.argv[2]), await rows(process.argv[3]));
JS
assert_empty "$scratch/index-stdout.err" "tag index stdout stderr"

run_native "$scratch/index-repo" "$inventory_root" fixture tag index
assert_status "$scratch/index-repo" 0 "tag index repo"
assert_empty "$scratch/index-repo.err" "tag index repo stderr"
assert_same "$scratch/index-stdout.out" \
  "$inventory_root/.firn-cache/tags.jsonl" "tag index persisted output"

printf 'tag-family: checking fact mutations, idempotence, and re-resolution\n' >&2
resolved() {
  sed -n '/^Resolved active modules/,$p' "$1.out" | tail -n +2 \
    | tr -d ' ' | paste -sd' '
}

mutate() {
  local name="$1" expect="$2"
  shift 2
  local root="$scratch/mutation-$name"
  local facts="$root/hosts/fixture/_generated-enables.gal"
  make_fixture "$root"
  cp "$facts" "$scratch/$name.before.gal"
  run_native "$scratch/$name.first" "$root" fixture "$@"
  assert_status "$scratch/$name.first" 0 "$name first call"
  assert_empty "$scratch/$name.first.err" "$name first stderr"
  cmp -s "$scratch/$name.before.gal" "$facts" \
    && die "$name reported an update without changing bytes"
  cp "$facts" "$scratch/$name.after.gal"
  run_native "$scratch/$name.first-status" "$root" fixture tag status fixture
  assert_status "$scratch/$name.first-status" 0 "$name status after first call"
  run_native "$scratch/$name.second" "$root" fixture "$@"
  if [[ "$name" == module-enable ]]; then
    assert_status "$scratch/$name.second" 1 "$name repeated refusal"
    assert_empty "$scratch/$name.second.out" "$name repeated stdout"
  else
    assert_status "$scratch/$name.second" 0 "$name repeated call"
    assert_empty "$scratch/$name.second.err" "$name repeated stderr"
    rg -q '^no change to ' "$scratch/$name.second.out" \
      || die "$name repeated call changed facts"
  fi
  assert_same "$scratch/$name.after.gal" "$facts" "$name repeated bytes"
  run_native "$scratch/$name.second-status" "$root" fixture tag status fixture
  assert_status "$scratch/$name.second-status" 0 "$name status after repeated call"
  resolved "$scratch/$name.first-status" >"$scratch/$name.first.set"
  resolved "$scratch/$name.second-status" >"$scratch/$name.second.set"
  assert_same "$scratch/$name.first.set" "$scratch/$name.second.set" \
    "$name resolved set"
  [[ "$(<"$scratch/$name.first.set")" == "$expect" ]] \
    || die "$name resolved '$(<"$scratch/$name.first.set")', expected '$expect'"
  printf 'tag-family: %s resolves %s after first and repeated calls\n' \
    "$name" "$expect" >&2
}

mutate tag-enable "alpha delta epsilon" tag enable creative
mutate tag-disable "alpha" tag disable desktop
mutate tag-opt-in "alpha delta epsilon" tag opt-in desktop+epsilon
mutate tag-opt-out "alpha delta" tag opt-out desktop+alpha
mutate module-disable "delta" module disable alpha
mutate module-enable "alpha delta gamma" module enable gamma

printf 'tag-family: checking refusal paths\n' >&2
refusal_root="$scratch/refusal-repo"
make_fixture "$refusal_root"
cp "$refusal_root/hosts/fixture/_generated-enables.gal" \
  "$scratch/refusal.before.gal"
run_native "$scratch/module-refusal" "$refusal_root" fixture module enable beta
assert_status "$scratch/module-refusal" 1 "module enable refusal"
assert_empty "$scratch/module-refusal.out" "module enable refusal stdout"
assert_same "$scratch/refusal.before.gal" \
  "$refusal_root/hosts/fixture/_generated-enables.gal" \
  "module enable refusal source"

run_native "$scratch/malformed" "$refusal_root" fixture \
  tag opt-in desktop-epsilon
assert_status "$scratch/malformed" 1 "malformed tag opt-in"
assert_empty "$scratch/malformed.out" "malformed tag opt-in stdout"
assert_same "$scratch/refusal.before.gal" \
  "$refusal_root/hosts/fixture/_generated-enables.gal" \
  "malformed tag opt-in source"

run_native "$scratch/malformed-missing" "$refusal_root" missing \
  tag opt-out desktop-epsilon
assert_status "$scratch/malformed-missing" 1 \
  "malformed tag opt-out on missing host"
assert_empty "$scratch/malformed-missing.out" \
  "malformed missing-host tag opt-out stdout"
[[ ! -e "$refusal_root/hosts/missing" ]] \
  || die "malformed leaf refusal created a host directory"

run_native "$scratch/missing-host" "$refusal_root" missing tag enable creative
assert_status "$scratch/missing-host" 1 "missing host mutation"
assert_empty "$scratch/missing-host.out" "missing host mutation stdout"
[[ ! -e "$refusal_root/hosts/missing" ]] \
  || die "missing host mutation created a host directory"

run_native "$scratch/missing-module" "$refusal_root" fixture tag show absent
assert_status "$scratch/missing-module" 1 "missing module show"
assert_empty "$scratch/missing-module.out" "missing module show stdout"

printf 'ok: Bun tag family resolution, inventory, and seeded properties pass\n'
