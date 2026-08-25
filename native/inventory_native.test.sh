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
    printf 'inventory-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-inventory-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'inventory-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'inventory-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

build_family() {
  local output="$scratch/build"
  mkdir -p "$output/node_modules/beagle"
  printf 'inventory-family: building closed Beagle/JS graph\n' >&2
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
  cp -- "$repo/native/inventory_family_test_host.mjs" \
    "$output/inventory_family_test_host.mjs"
}

datum="$beagle/native-core/src/beagle/datum_reader.bjs"
json="$beagle/native-core/src/native/json.bjs"
tag_resolve="$repo/native/tag_resolve.bjs"
tag_inputs="$repo/native/tag_inputs.bjs"
tag_driver="$repo/native/tag_resolve_driver.bjs"
tag_family="$repo/native/tag_resolve_family.bjs"
inventory="$repo/native/inventory.bjs"

build_family "$datum" "$json" "$tag_resolve" "$tag_inputs" \
  "$tag_driver" "$tag_family" "$inventory" \
  "$repo/native/inventory_test.bjs" "$repo/native/inventory_family.bjs"

printf 'inventory-native: running pure fixtures\n' >&2
timeout --foreground 30 bun "$scratch/build/inventory_family_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure inventory fixtures failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

fixture="$scratch/repo"
mkdir -p \
  "$fixture/modules/alpha" \
  "$fixture/modules/beta" \
  "$fixture/modules/gamma" \
  "$fixture/modules/orphan" \
  "$fixture/hosts/alpha-host" \
  "$fixture/hosts/zeta-host"

cat >"$fixture/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF
cat >"$fixture/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:tags [terminal]})
EOF
cat >"$fixture/modules/gamma/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:tags [desktop]})
EOF
cat >"$fixture/modules/orphan/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF

cat >"$fixture/hosts/alpha-host/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
{:platform linux
 :enabled [terminal]
 :disabled []}
EOF
cat >"$fixture/hosts/zeta-host/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
{:platform linux
 :enabled [desktop]
 :disabled []}
EOF

cat >"$fixture/hosts/alpha-host/configuration.bnix" <<'EOF'
#lang beagle/nix
(ns configuration)
(nix/module [config lib pkgs ...]
  {:myConfig.modules.alpha.enable true
   :myConfig.modules.beta
    {:enable false
     :port 44}
   :myConfig.modules.gamma.someOption "configured"
   :imports [(p "./_generated-enables.nix")]})
EOF
cat >"$fixture/hosts/zeta-host/configuration.bnix" <<'EOF'
#lang beagle/nix
(ns configuration)
(nix/module [config lib pkgs ...]
  {:myConfig.modules.beta.enable true
   :imports [(p "./_generated-enables.nix")]})
EOF

cat >"$fixture/hosts/alpha-host/_generated-enables.bnix" <<'EOF'
this output artifact is deliberately not valid Beagle source
EOF
cat >"$fixture/hosts/zeta-host/_generated-enables.bnix" <<'EOF'
#lang beagle/nix
(ns _generated-enables)
(nix/module [config lib pkgs ...]
  {:myConfig.modules.orphan.enable true})
EOF

run_cli() {
  local name="$1"
  shift
  set +e
  timeout --foreground 30 env \
    -u FIRN_TRACE_ID -u FIRN_TRACE_PATH \
    FIRN_REPO="$fixture" FIRN_HOST=alpha-host \
    env FIRN_INVENTORY_MODULE="$scratch/build/firn/inventory-family.js" \
      bun "$repo/native/inventory_host.mjs" "$@" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  [[ "$status" == 0 ]] || die "$name returned $status"
  [[ ! -s "$scratch/$name.err" ]] || die "$name wrote stderr"
}

assert_output() {
  local name="$1" expected="$2"
  if ! cmp -s "$expected" "$scratch/$name.out"; then
    diff -u "$expected" "$scratch/$name.out" >&2 || true
    die "$name stdout changed"
  fi
}

printf 'inventory-native: running exact CLI fixture\n' >&2

run_cli module-all module list all
cat >"$scratch/module-all.expected" <<'EOF'
Modules (4):
  myConfig.modules.alpha
  myConfig.modules.beta
  myConfig.modules.gamma
  myConfig.modules.orphan
EOF
assert_output module-all "$scratch/module-all.expected"

run_cli module-used module list used
cat >"$scratch/module-used.expected" <<'EOF'
Used modules (3):
  alpha  (alpha-host)
  beta  (alpha-host, zeta-host, via tag@alpha-host)
  gamma  (alpha-host, via tag@zeta-host)
EOF
assert_output module-used "$scratch/module-used.expected"

run_cli module-unused module list unused
cat >"$scratch/module-unused.expected" <<'EOF'
Unreferenced modules (1):
  orphan
EOF
assert_output module-unused "$scratch/module-unused.expected"

run_cli module-refs module refs beta
cat >"$scratch/module-refs.expected" <<'EOF'
Hosts (direct, from configuration.bnix):
  alpha-host
  zeta-host

Hosts (via tag resolution):
  alpha-host
EOF
assert_output module-refs "$scratch/module-refs.expected"

run_cli module-status module status all
cat >"$scratch/module-status.expected" <<'EOF'
Enabled in alpha-host:
  myConfig.modules.alpha

Explicitly disabled in alpha-host:
  myConfig.modules.beta
EOF
assert_output module-status "$scratch/module-status.expected"

run_cli host-list host list all
cat >"$scratch/host-list.expected" <<'EOF'
Hosts (2):
  alpha-host
  zeta-host
EOF
assert_output host-list "$scratch/host-list.expected"

run_cli host-status host status zeta-host
cat >"$scratch/host-status.expected" <<'EOF'
Enabled in zeta-host:
  myConfig.modules.beta
EOF
assert_output host-status "$scratch/host-status.expected"

printf 'ok: Beagle/JS Firn inventory matches the canonical controlled fixture\n'
