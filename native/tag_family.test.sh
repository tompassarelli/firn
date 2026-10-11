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
    printf 'tag-family: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
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

[[ -x "$beagle/bin/beagle-build-all" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"
command -v bun >/dev/null 2>&1 || die "Bun is unavailable"

build_family() {
  local output="$scratch/build"
  printf 'tag-family: building closed Beagle/JS graph\n' >&2
  mkdir -p "$output/node_modules/beagle"
  timeout --foreground 60 "$beagle/bin/beagle-build-all" "$@" \
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
  [[ -f "$output/firn/tag-family.js" ]] \
    || die "compiled family module is unavailable"
}

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

datum="$beagle/native-core/src/beagle/datum_reader.bjs"
json="$beagle/native-core/src/native/json.bjs"
resolve="$repo/native/tag_resolve.bjs"
inputs="$repo/native/tag_inputs.bjs"
resolve_driver="$repo/native/tag_resolve_driver.bjs"
resolve_family="$repo/native/tag_resolve_family.bjs"
commands="$repo/native/tag_commands.bjs"
commands_driver="$repo/native/tag_commands_driver.bjs"
commands_family="$repo/native/tag_commands_family.bjs"
family="$repo/native/firn_tag_family.bjs"
resolve_property="$repo/native/tag_resolve_property_test.bjs"
mutation_property="$repo/native/tag_mutation_property_test.bjs"

build_family \
  "$datum" "$json" "$resolve" "$inputs" "$resolve_driver" \
  "$resolve_family" "$commands" "$commands_driver" "$commands_family" \
  "$family" "$resolve_property" "$mutation_property"
printf 'tag-family: checking seeded algebra and mutation properties (seed 73421)\n' >&2
timeout --foreground 30 bun --eval '
  const resolve = await import(process.argv[1]);
  const mutation = await import(process.argv[2]);
  process.exitCode = resolve["run-properties"](process.env.CI ? 512 : 128) + mutation["run-properties"](process.env.CI ? 512 : 128);
' "$scratch/build/firn/tag-resolve-property-test.js" \
  "$scratch/build/firn/tag-mutation-property-test.js" \
  || die "seeded tag properties failed"
runtime=(env FIRN_TAG_MODULE="$scratch/build/firn/tag-family.js" \
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
  cat >"$root/flake.bnix" <<'EOF'
#lang beagle/nix
(ns flake)
{}
EOF
  cat >"$root/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [desktop terminal]})
EOF
  cat >"$root/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [desktop]})
EOF
  cat >"$root/modules/delta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags-opt-in [desktop]})
EOF
  cat >"$root/modules/epsilon/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [creative]
   :tags-opt-in [desktop]})
EOF
  cat >"$root/modules/gamma/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [terminal]})
EOF
  cat >"$root/modules/plain/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:config {}})
EOF
  cat >"$root/hosts/$host/enabled-tags.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   terminal]
 :disabled [gamma]
}
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
  "$inventory_root/.beagle-cache/tags.jsonl" "tag index persisted output"

printf 'tag-family: checking atomic mutation, idempotence, and re-resolution\n' >&2
mutation_root="$scratch/mutation-repo"
host_file="$mutation_root/hosts/fixture/enabled-tags.bnix"
make_fixture "$mutation_root"
cp "$host_file" "$scratch/mutation.before.bnix"
run_native "$scratch/mutation.first" "$mutation_root" fixture tag enable creative
assert_status "$scratch/mutation.first" 0 "first mutation"
assert_empty "$scratch/mutation.first.err" "mutation stderr"
cmp -s "$scratch/mutation.before.bnix" "$host_file" \
  && die "mutation reported an update without changing bytes"
cp "$host_file" "$scratch/mutation.after.bnix"
run_native "$scratch/mutation.second" "$mutation_root" fixture tag enable creative
assert_status "$scratch/mutation.second" 0 "idempotent mutation"
assert_empty "$scratch/mutation.second.err" "idempotent stderr"
assert_same "$scratch/mutation.after.bnix" "$host_file" "idempotent bytes"
run_native "$scratch/mutation.status" "$mutation_root" fixture tag status fixture
assert_status "$scratch/mutation.status" 0 "resolver after mutation"
rg -q '^  epsilon$' "$scratch/mutation.status.out" || die "new tag did not resolve through the host loader"
assert_empty "$scratch/mutation.status.err" "resolver after mutation stderr"

printf 'tag-family: checking refusal paths\n' >&2
refusal_root="$scratch/refusal-repo"
make_fixture "$refusal_root"
cp "$refusal_root/hosts/fixture/enabled-tags.bnix" \
  "$scratch/refusal.before.bnix"
run_native "$scratch/module-refusal" "$refusal_root" fixture module enable beta
assert_status "$scratch/module-refusal" 1 "module enable refusal"
assert_empty "$scratch/module-refusal.out" "module enable refusal stdout"
assert_same "$scratch/refusal.before.bnix" \
  "$refusal_root/hosts/fixture/enabled-tags.bnix" \
  "module enable refusal source"

run_native "$scratch/malformed" "$refusal_root" fixture \
  tag opt-in desktop-epsilon
assert_status "$scratch/malformed" 1 "malformed tag opt-in"
assert_empty "$scratch/malformed.out" "malformed tag opt-in stdout"
assert_same "$scratch/refusal.before.bnix" \
  "$refusal_root/hosts/fixture/enabled-tags.bnix" \
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
