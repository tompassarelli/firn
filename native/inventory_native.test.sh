#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
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

command -v galileo >/dev/null || [[ -x "${FIRN_RUNTIME_BIN:-}/galileo" ]] \
  || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"



printf 'inventory-native: running pure fixtures\n' >&2
timeout --foreground 30 bun "$repo/native/inventory_family_test_host.mjs" \
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
git init -q -b main "$fixture"

cat >"$fixture/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF
cat >"$fixture/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF
cat >"$fixture/modules/gamma/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF
cat >"$fixture/modules/orphan/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...] {:config {}})
EOF

mkdir -p "$fixture/config"
cat >"$fixture/config/tags.gal" <<'EOF'
use firn/tags

desktop is a Tag
terminal is a Tag
alpha is a Module
beta is a Module
gamma is a Module
orphan is a Module
beta is tagged terminal
gamma is tagged desktop
linux is a Platform
linux allows every module
alpha-host is a Host
alpha-host runs linux
alpha-host enables terminal
zeta-host is a Host
zeta-host runs linux
zeta-host enables desktop
EOF

cat >"$fixture/hosts/alpha-host/configuration.gal" <<'EOF'
use firn/tags

alpha-host turns on alpha
alpha-host turns off beta

nix file
  arguments: config, lib, pkgs, ...
  value
    for ?m where alpha-host turns on ?m
      myConfig.modules.{?m}.enable: true
    for ?m where alpha-host turns off ?m
      myConfig.modules.{?m}.enable: false
    myConfig.modules.beta.port: 44
    myConfig.modules.gamma.someOption: "configured"
    imports: [./_generated-enables.nix]
EOF
cat >"$fixture/hosts/zeta-host/configuration.gal" <<'EOF'
use firn/tags

zeta-host turns on beta

nix file
  arguments: config, lib, pkgs, ...
  value
    for ?m where zeta-host turns on ?m
      myConfig.modules.{?m}.enable: true
    imports: [./_generated-enables.nix]
EOF

run_cli() {
  local name="$1"
  shift
  set +e
  timeout --foreground 30 env \
    -u FIRN_TRACE_ID -u FIRN_TRACE_PATH \
    FIRN_REPO="$fixture" FIRN_HOST=alpha-host \
    env FIRN_INVENTORY_MODULE="$repo/native/inventory_family.ts" \
      bun "$repo/native/inventory_host.mjs" "$@" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  [[ "$status" == 0 ]] || die "$name returned $status"
  [[ ! -s "$scratch/$name.err" ]] || die "$name wrote stderr"
}

assert_output() {
  local name="$1" expected="$2"
  awk '/^  / {$1=$1; print}' "$expected" >"$scratch/$name.expected.rows"
  awk '/^  / {$1=$1; print}' "$scratch/$name.out" >"$scratch/$name.actual.rows"
  if ! cmp -s "$scratch/$name.expected.rows" "$scratch/$name.actual.rows"; then
    diff -u "$expected" "$scratch/$name.out" >&2 || true
    die "$name stdout changed"
  fi
}

printf 'inventory-native: running CLI inventory scenario\n' >&2

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
  beta  (alpha-host, zeta-host)
  gamma  (via tag@zeta-host)
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
Hosts (direct, from configuration.gal):
  alpha-host
  zeta-host

Hosts (via tag resolution):
  (none)
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
