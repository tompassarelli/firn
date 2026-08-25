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
    printf 'schema-transaction-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-schema-transaction.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'schema-transaction-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'schema-transaction-native: %s\n' "$*" >&2
  exit 1
}

for command in bun git rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bjs"
core="$repo/native/schema_transaction.bjs"
pure="$repo/native/schema_transaction_test.bjs"
native="$repo/native/schema_transaction_native.bjs"

printf 'schema-transaction-js: building exact focused bundle\n' >&2
mkdir -p "$scratch/out"
timeout --foreground 180 "$beagle/bin/beagle-build-all" \
  "$json" "$core" "$pure" "$native" --out "$scratch/out" \
  >"$scratch/pure.build.out" 2>"$scratch/pure.build.err" \
  || {
    sed -n '1,260p' "$scratch/pure.build.err" >&2
    die "focused Beagle/JS bundle compilation failed"
  }
[[ -f "$scratch/out/firn/schema-transaction-test.js" ]] \
  || die "focused pure test module is missing"
[[ -f "$scratch/out/firn/schema-transaction-native.js" ]] \
  || die "schema host-plan module is missing"
mkdir -p "$scratch/out/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$scratch/out/node_modules/beagle/core.js"
printf '%s\n' '{"type":"module"}' \
  >"$scratch/out/node_modules/beagle/package.json"

printf 'schema-transaction-native: focused pure policy fixtures\n' >&2
FIRN_SCHEMA_TEST_MODULE="$scratch/out/firn/schema-transaction-test.js" \
timeout --foreground 30 bun --eval \
  'const module = await import(process.env.FIRN_SCHEMA_TEST_MODULE); process.exitCode = module.run([]);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || {
    sed -n '1,200p' "$scratch/pure.out" >&2
    sed -n '1,200p' "$scratch/pure.err" >&2
    die "focused pure policy fixtures failed"
  }
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == "11" ]] \
  || die "focused pure policy fixture count changed"
[[ ! -s "$scratch/pure.err" ]] \
  || die "focused pure policy fixtures wrote stderr"

printf 'schema-transaction-native: real flake.lock fingerprint\n' >&2
FIRN_SCHEMA_TEST_MODULE="$scratch/out/firn/schema-transaction-test.js" \
FIRN_SCHEMA_REAL_LOCK="$repo/flake.lock" \
timeout --foreground 30 bun --eval '
  const module = await import(process.env.FIRN_SCHEMA_TEST_MODULE);
  const lock = await Bun.file(process.env.FIRN_SCHEMA_REAL_LOCK).text();
  if (!module["real-lock-fingerprint-valid?"](lock)) process.exit(1);
' >"$scratch/real-lock.out" 2>"$scratch/real-lock.err" \
  || {
    sed -n '1,200p' "$scratch/real-lock.err" >&2
    die "real flake.lock fingerprint failed"
  }
[[ ! -s "$scratch/real-lock.err" ]] \
  || die "real flake.lock fingerprint wrote stderr"

printf 'ok: Beagle/JS schema authority policy and Bun transaction boundary are checked\n'
