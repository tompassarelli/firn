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

for module in alpha beta gamma orphan; do
  printf '{ ... }: {}\n' >"$fixture/modules/$module/default.nix"
done
printf '%s\n' '{"tags":["terminal"]}' >"$fixture/modules/beta/metadata.json"
printf '%s\n' '{"tags":["desktop"]}' >"$fixture/modules/gamma/metadata.json"
printf '%s\n' '{"platform":"linux","enables":["terminal"],"turnsOn":["alpha"],"turnsOff":["beta"]}' >"$fixture/hosts/alpha-host/tags.json"
printf '%s\n' '{"platform":"linux","enables":["desktop"],"turnsOn":["beta"]}' >"$fixture/hosts/zeta-host/tags.json"

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
Hosts (direct, from configuration.nix):
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

printf 'ok: TypeScript/Bun Firn inventory matches the canonical controlled fixture\n'
